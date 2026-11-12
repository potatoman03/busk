import CoreGraphics
import Foundation

/// Raw measurements for one detected jump shot.
struct ShotMetrics: Codable, Equatable, Sendable {
    /// Tightest elbow angle while loading the ball (degrees).
    var setElbowAngle: Double
    /// Horizontal elbow-to-wrist offset at the set point, as a fraction of forearm length. 0 = elbow straight under the ball.
    var elbowOffset: Double
    /// Most extended elbow angle around release (degrees). 180 = locked out.
    var releaseElbowAngle: Double
    /// Wrist height above the nose at release, in torso lengths.
    var releaseHeight: Double
    /// Shoulder-to-wrist elevation at release in degrees above horizontal; proxy for launch arc. Side view only.
    var releaseAngle: Double?
    /// Seconds the shooting hand stayed up near its peak after release.
    var followThrough: Double
    /// Tightest knee angle during the dip (degrees), if legs were visible.
    var kneeAngle: Double?
}

enum ShotPhase: String, Sendable {
    case waiting = "Waiting for your shot"
    case gathering = "Gathering"
    case followThrough = "Follow through"
    case recovering = "Reset"
}

/// Turns a stream of pose frames into detected shots.
final class ShotAnalyzer {
    struct Config {
        var gatherMaxElbowAngle: Double = 130
        var releaseMinElbowAngle: Double = 150
        var maxGatherDuration: TimeInterval = 2.5
        var releaseWindow: TimeInterval = 0.25
        var maxFollowThrough: TimeInterval = 1.5
        var dipLookback: TimeInterval = 1.2
        /// How far (degrees about the shoulder) the arm may drop from its peak and still count as holding the follow-through.
        var holdDropDegrees: Double = 10
        var peakToleranceDegrees: Double = 3
    }

    let handedness: Handedness
    let view: CameraView
    var config = Config()

    private(set) var phase: ShotPhase = .waiting

    private var history: [PoseFrame] = []
    private var gatherStart: TimeInterval = 0
    private var setElbowAngle = Double.infinity
    private var setElbowOffset = 0.0
    private var setElbowLifted = false
    private var setElbowOffsetAngle = Double.infinity
    private var minKnee: Double?
    private var releaseTime: TimeInterval = 0
    private var releaseElbow = 0.0
    private var releaseHeight = -Double.infinity
    private var releaseAngle: Double?
    private var holdSamples: [(t: TimeInterval, elevation: Double, aboveHead: Bool)] = []

    init(handedness: Handedness, view: CameraView) {
        self.handedness = handedness
        self.view = view
    }

    func reset() {
        phase = .waiting
        history.removeAll()
    }

    /// Feeds one frame; returns metrics when a shot completes.
    func process(_ frame: PoseFrame) -> ShotMetrics? {
        guard let s = frame[handedness.shoulder], let e = frame[handedness.elbow], let w = frame[handedness.wrist],
              let head = frame[.nose] ?? frame[.neck] else { return nil }

        history.append(frame)
        history.removeAll { frame.timestamp - $0.timestamp > config.dipLookback + config.maxGatherDuration }

        let t = frame.timestamp
        let elbowAngle = Geometry.angle(s, e, w)
        let wristAboveShoulder = w.y < s.y
        let wristAboveHead = w.y < head.y

        switch phase {
        case .waiting:
            if wristAboveShoulder && elbowAngle < config.gatherMaxElbowAngle {
                phase = .gathering
                gatherStart = t
                setElbowAngle = .infinity
                setElbowLifted = false
                setElbowOffsetAngle = .infinity
                minKnee = kneeAngle(in: history.filter { t - $0.timestamp <= config.dipLookback })
                trackGather(elbowAngle: elbowAngle, shoulder: s, elbow: e, wrist: w, frame: frame)
            }
        case .gathering:
            trackGather(elbowAngle: elbowAngle, shoulder: s, elbow: e, wrist: w, frame: frame)
            if elbowAngle >= config.releaseMinElbowAngle && wristAboveHead {
                phase = .followThrough
                releaseTime = t
                releaseElbow = elbowAngle
                releaseHeight = -.infinity
                releaseAngle = nil
                holdSamples = [(t, Geometry.elevation(from: s, to: w), wristAboveHead)]
                trackRelease(elbowAngle: elbowAngle, shoulder: s, wrist: w, head: head, frame: frame)
            } else if t - gatherStart > config.maxGatherDuration || !wristAboveShoulder && elbowAngle > config.gatherMaxElbowAngle {
                phase = .waiting
            }
        case .followThrough:
            if t - releaseTime <= config.releaseWindow {
                trackRelease(elbowAngle: elbowAngle, shoulder: s, wrist: w, head: head, frame: frame)
            }
            holdSamples.append((t, Geometry.elevation(from: s, to: w), wristAboveHead))
            if !wristAboveShoulder || t - releaseTime >= config.maxFollowThrough {
                phase = wristAboveShoulder ? .recovering : .waiting
                return ShotMetrics(
                    setElbowAngle: setElbowAngle,
                    elbowOffset: setElbowOffset,
                    releaseElbowAngle: releaseElbow,
                    releaseHeight: releaseHeight,
                    releaseAngle: releaseAngle,
                    followThrough: holdDuration(),
                    kneeAngle: minKnee
                )
            }
        case .recovering:
            if !wristAboveShoulder { phase = .waiting }
        }
        return nil
    }

    private func trackGather(elbowAngle: Double, shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint, frame: PoseFrame) {
        if let k = kneeAngle(in: [frame]) { minKnee = min(minKnee ?? k, k) }
        setElbowAngle = min(setElbowAngle, elbowAngle)
        // Set point: the most loaded arm once the elbow has lifted to shoulder height.
        let lifted = elbow.y <= shoulder.y
        if lifted && !setElbowLifted {
            setElbowLifted = true
            setElbowOffsetAngle = .infinity
        }
        guard lifted == setElbowLifted, elbowAngle < setElbowOffsetAngle else { return }
        setElbowOffsetAngle = elbowAngle
        let forearm = max(Geometry.distance(elbow, wrist), 0.0001)
        setElbowOffset = Double(abs(elbow.x - wrist.x)) / forearm
    }

    private func trackRelease(elbowAngle: Double, shoulder: CGPoint, wrist: CGPoint, head: CGPoint, frame: PoseFrame) {
        releaseElbow = max(releaseElbow, elbowAngle)
        let torso = torsoLength(frame) ?? 0.22
        let height = Double(head.y - wrist.y) / torso
        if height > releaseHeight {
            releaseHeight = height
            if view == .side { releaseAngle = Geometry.elevation(from: shoulder, to: wrist) }
        }
    }

    /// Time the arm stayed up at its finish: from reaching the peak to dropping away from it.
    private func holdDuration() -> Double {
        guard let peak = holdSamples.map(\.elevation).max(),
              let start = holdSamples.firstIndex(where: { $0.elevation >= peak - config.peakToleranceDegrees }) else { return 0 }
        var end = start
        while end + 1 < holdSamples.count, holdSamples[end + 1].aboveHead,
              holdSamples[end + 1].elevation >= peak - config.holdDropDegrees { end += 1 }
        return holdSamples[end].t - holdSamples[start].t
    }

    private func torsoLength(_ frame: PoseFrame) -> Double? {
        guard let s = frame[handedness.shoulder], let h = frame[handedness.hip] else { return nil }
        let d = Geometry.distance(s, h)
        return d > 0.01 ? d : nil
    }

    private func kneeAngle(in frames: [PoseFrame]) -> Double? {
        frames.compactMap { f -> Double? in
            guard let h = f[handedness.hip], let k = f[handedness.knee], let a = f[handedness.ankle] else { return nil }
            return Geometry.angle(h, k, a)
        }.min()
    }
}
