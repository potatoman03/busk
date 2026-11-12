import CoreGraphics
import Foundation

/// Raw measurements for one detected jump shot. Lengths are in body heights; times in seconds.
/// Optional values are nil when the camera angle or the visible joints can't show them.
struct ShotMetrics: Codable, Equatable, Sendable {
    /// Nil when the camera angle is unknown: only checks that work from any angle are measured.
    var view: CameraView?
    /// Shooting wrist height above the shooting shoulder at the set point. Negative = pushing from the chest.
    var setPointHeight: Double
    /// Front view: sideways elbow-to-wrist offset at the set point. 0 = elbow straight under the ball.
    var elbowFlare: Double?
    /// Side view: shoulder-to-wrist elevation at release, degrees above horizontal.
    var armAngle: Double?
    /// Time the shooting hand stayed above the head after release.
    var followThrough: Double
    /// How far the hips sank toward the ankles in the dip.
    var legDrive: Double?
    /// Release time relative to the jump's peak, in half air-times: 0 = at the peak, 1 = on landing. Nil without a jump.
    var releaseTiming: Double?
    /// Time the ball stopped at the set point before the release.
    var hitch: Double
    /// Distance between the takeoff and landing spots.
    var drift: Double?
    /// Front view: guide hand travel just after release.
    var guideHandPush: Double?

    /// Estimated launch angle: the ball leaves about 20° flatter than the arm points.
    var launchAngle: Double? { armAngle.map { $0 - 20 } }
}

enum ShotPhase: String, Sendable {
    case waiting = "Waiting for your shot"
    case gathering = "Gathering"
    case followThrough = "Follow through"
    case recovering = "Reset"
}

/// Turns a stream of pose frames into detected shots. Each shot is measured over the whole
/// buffered motion (dip, set, release, follow-through and landing) once it has finished.
final class ShotAnalyzer {
    struct Config {
        var releaseMinElbowAngle: Double = 140
        var gatherMaxElbowAngle: Double = 130
        /// Seconds of motion kept before the release.
        var lookback: TimeInterval = 2.0
        /// Seconds after the release before the shot is measured (lets the landing happen).
        var settle: TimeInterval = 0.9
        var maxFollowThrough: TimeInterval = 1.5
        /// Wrist speed (body heights / s) below which the ball counts as stopped.
        var pauseSpeed: Double = 0.08
    }

    let handedness: Handedness
    let view: CameraView?
    var config = Config()

    private(set) var phase: ShotPhase = .waiting
    private var history: [PoseFrame] = []
    private var releaseTime: TimeInterval?
    private var armDropped = false

    init(handedness: Handedness, view: CameraView?) {
        self.handedness = handedness
        self.view = view
    }

    func reset() {
        phase = .waiting
        history.removeAll()
        releaseTime = nil
    }

    /// Feeds one frame; returns metrics when a shot completes.
    func process(_ frame: PoseFrame) -> ShotMetrics? {
        history.append(frame)
        let t = frame.timestamp
        history.removeAll { t - $0.timestamp > config.lookback + config.maxFollowThrough + 0.5 }
        let s = frame.point(handedness.shoulder), w = frame.point(handedness.wrist)
        if let rt = releaseTime {
            if let s, let w, w.y > s.y { armDropped = true }
            guard t - rt >= config.maxFollowThrough || (armDropped && t - rt >= config.settle) else { return nil }
            releaseTime = nil
            phase = armDropped ? .waiting : .recovering
            return measure(release: rt)
        }
        guard let s, let w, let e = frame.point(handedness.elbow), let head = frame.point(.nose) ?? frame.point(.neck) else { return nil }
        let elbowAngle = Geometry.angle(s, e, w)
        switch phase {
        case .waiting, .gathering:
            if w.y < head.y && elbowAngle >= config.releaseMinElbowAngle && phase == .gathering {
                phase = .followThrough
                releaseTime = t
                armDropped = false
            } else if elbowAngle < config.gatherMaxElbowAngle, let hip = frame.point(handedness.hip), w.y < (s.y + hip.y) / 2 {
                phase = .gathering
            } else if phase == .gathering, w.y > (frame.point(handedness.hip)?.y ?? 1) {
                phase = .waiting
            }
        case .followThrough:
            break
        case .recovering:
            if w.y > s.y { phase = .waiting }
        }
        return nil
    }

    // MARK: - Measurement

    private struct Sample {
        var t: TimeInterval
        var shoulder: CGPoint, elbow: CGPoint, wrist: CGPoint, head: CGPoint
        var guide: CGPoint?, root: CGPoint?, ankle: CGPoint?
        var span: Double? // nose-to-ankle height
    }

    private func measure(release rt: TimeInterval) -> ShotMetrics? {
        let guideSide: Handedness = handedness == .right ? .left : .right
        let samples: [Sample] = history.filter { $0.timestamp >= rt - config.lookback }.compactMap { f in
            guard let s = f.point(handedness.shoulder), let e = f.point(handedness.elbow), let w = f.point(handedness.wrist),
                  let head = f.point(.nose) ?? f.point(.neck) else { return nil }
            let ankles = [f.point(.leftAnkle), f.point(.rightAnkle)].compactMap { $0 }
            let ankle = ankles.isEmpty ? nil : CGPoint(x: ankles.map(\.x).reduce(0, +) / CGFloat(ankles.count),
                                                       y: ankles.map(\.y).reduce(0, +) / CGFloat(ankles.count))
            return Sample(t: f.timestamp, shoulder: s, elbow: e, wrist: w, head: head, guide: f.point(guideSide.wrist),
                          root: f.point(.root), ankle: ankle, span: ankle.map { Double($0.y - head.y) })
        }
        guard samples.count >= 8 else { return nil }
        let n = samples.count
        let dt = max((samples[n - 1].t - samples[0].t) / Double(n - 1), 1.0 / 120)

        // Body height: nose-to-ankle is ~87% of standing height. Fall back to the torso when the feet are out of frame.
        let spans = samples.compactMap(\.span)
        let height: Double
        if spans.count >= n / 2, let tall = spans.sorted().dropFirst(spans.count / 10).last {
            height = tall / 0.87
        } else {
            let t = samples.compactMap { s in s.root.map { Double(abs($0.y - s.shoulder.y)) } }.sorted()
            height = (t.isEmpty ? 0.25 : t[t.count / 2]) / 0.29
        }
        let H = max(height, 0.05)

        // Release: the first frame the shooting wrist reaches the top of its extension.
        // The trigger can fire early (from the front, a bent arm can look straight), so look ahead for the real top.
        let around = samples.indices.filter { samples[$0].t >= rt - 0.3 && samples[$0].t <= rt + 0.6 }
        let lift = { (i: Int) in Double(samples[i].shoulder.y - samples[i].wrist.y) / H }
        let peak = around.map(lift).max() ?? 0
        let rel = around.first { lift($0) >= peak - 0.02 } ?? (samples.firstIndex { $0.t >= rt } ?? n / 2)

        // Wrist speed relative to the shoulder, in body heights per second.
        var speed = [Double](repeating: 9, count: n)
        for i in 1..<(n - 1) {
            let a = samples[i - 1], b = samples[i + 1]
            let dx = Double((b.wrist.x - b.shoulder.x) - (a.wrist.x - a.shoulder.x))
            let dy = Double((b.wrist.y - b.shoulder.y) - (a.wrist.y - a.shoulder.y))
            speed[i] = hypot(dx, dy) / H / (2 * dt)
        }

        // Set point: walk back from the fastest moment of the release push to where the ball last stopped.
        let lo = max(1, rel - Int(0.8 / dt))
        let pushStart = max(lo, rel - Int(0.27 / dt))
        var setIdx = (pushStart..<max(pushStart + 1, rel)).max { speed[$0] < speed[$1] } ?? max(lo, rel - 1)
        while setIdx > lo && speed[setIdx - 1] <= speed[setIdx] { setIdx -= 1 }
        var a = setIdx, b = setIdx
        while a > lo && speed[a - 1] < config.pauseSpeed { a -= 1 }
        while b < rel - 1 && speed[b + 1] < config.pauseSpeed { b += 1 }
        let hitch = speed[setIdx] < config.pauseSpeed ? Double(b - a + 1) * dt : 0
        let set = samples[setIdx]
        let setPointHeight = Double(set.shoulder.y - set.wrist.y) / H

        let elbowFlare = view == .front ? Double(abs(set.elbow.x - set.wrist.x)) / H : nil

        var armAngle: Double?
        if view == .side {
            armAngle = (max(0, rel - 2)...min(n - 1, rel + 3)).map { Geometry.elevation(from: samples[$0].shoulder, to: samples[$0].wrist) }.max()
        }

        // Follow-through lasts until the shooting hand is first seen back below the head (frames Vision missed don't end it).
        let follow = Array(samples[rel...])
        let dropped = follow.indices.first { i in
            i + 1 < follow.count && follow[i].wrist.y >= follow[i].head.y && follow[i + 1].wrist.y >= follow[i + 1].head.y
                && follow[i].t - samples[rel].t <= 1.0
        }.map { follow[$0] }
        // If the hand is never seen coming down (the person was lost from view), the finish isn't judged as short.
        let followThrough = min(1.0, (dropped?.t ?? .infinity) - samples[rel].t)

        // Legs: how far the hips sink toward the ankles before the release.
        var legDrive: Double?
        let legs = samples[..<rel].compactMap { s -> Double? in
            guard let r = s.root, let k = s.ankle else { return nil }
            return Double(k.y - r.y) / H
        }
        if legs.count >= 5, let hi = legs.max(), let low = legs.min() { legDrive = hi - low }

        // Jump: frames where the feet are clearly off the floor. Timing and drift are only judged on a real jump.
        var releaseTiming: Double?
        var drift: Double?
        let feet = samples.map { s in s.ankle.map { -Double($0.y) / H } }
        let known = feet.indices.filter { feet[$0] != nil }
        if let firstFoot = known.first, let lastFoot = known.last,
           let top = known.max(by: { feet[$0]! < feet[$1]! }), feet[top]! > feet[firstFoot]! + 0.012 {
            let floor0 = feet[firstFoot]!, floor1 = feet[lastFoot]!
            var s0 = top, s1 = top
            while s0 > 0, let f = feet[s0 - 1], f > floor0 + 0.012 { s0 -= 1 }
            while s1 < n - 1, let f = feet[s1 + 1], f > floor1 + 0.012 { s1 += 1 }
            let air = s1 - s0 + 1
            if air >= 3, rel >= s0 - 2, rel <= s1 + 2 {
                releaseTiming = Double(rel - top) / (Double(air) / 2)
                let takeoff = samples[..<s0].last { $0.ankle != nil } ?? samples[firstFoot]
                let settled = samples.last { $0.ankle != nil && $0.t <= samples[s1].t + 0.6 } ?? samples[lastFoot]
                if let a0 = takeoff.ankle, let a1 = settled.ankle {
                    var d = Double(abs(a1.x - a0.x)) / H
                    if view == .front, let h0 = takeoff.span, let h1 = settled.span, h1 > 0 {
                        d = max(d, abs(1 - h0 / h1) * 3.1) // getting bigger or smaller = moving toward or away from the camera
                    }
                    drift = d
                }
            }
        }

        var guideHandPush: Double?
        if view == .front, rel + 4 < n, let g0 = samples[rel].guide, let g1 = samples[rel + 4].guide,
           let r0 = samples[rel].root, let r1 = samples[rel + 4].root {
            guideHandPush = hypot(Double((g1.x - g0.x) - (r1.x - r0.x)), Double((g1.y - g0.y) - (r1.y - r0.y))) / H
        }

        return ShotMetrics(view: view, setPointHeight: setPointHeight, elbowFlare: elbowFlare, armAngle: armAngle,
                           followThrough: followThrough, legDrive: legDrive, releaseTiming: releaseTiming,
                           hitch: hitch, drift: drift, guideHandPush: guideHandPush)
    }
}
