import CoreGraphics
import Foundation

/// Generates synthetic side-view pose sequences of a jump shot. Drives demo mode (simulator, UI tests) and unit tests.
struct ShotSimulator {
    struct Style: Equatable {
        var name: String
        /// Forearm tilt off vertical at the set point, degrees. 0 = elbow under the ball.
        var elbowFlare: Double = 0
        /// Upper-arm elevation at release, degrees above horizontal.
        var releaseElevation: Double = 65
        /// Elbow interior angle at release.
        var releaseExtension: Double = 172
        /// Seconds the hand stays up after release.
        var followThroughHold: Double = 0.6
        /// How far the knee travels forward in the dip (normalized). ~0.06 is a good bend.
        var kneeForward: Double = 0.06

        static let good = Style(name: "Good form")
        static let flaredElbow = Style(name: "Flared elbow", elbowFlare: 50)
        static let flat = Style(name: "Flat shot", releaseElevation: 30, releaseExtension: 168)
        static let noFollowThrough = Style(name: "No follow-through", followThroughHold: 0.05)
        static let stiffLegs = Style(name: "Stiff legs", kneeForward: 0.015)
        static let demoRotation: [Style] = [.good, .flaredElbow, .flat, .noFollowThrough, .stiffLegs, .good]
    }

    var fps: Double = 30
    var handedness: Handedness = .right
    /// Horizontal position of the shooter in the frame.
    var centerX: CGFloat = 0.5

    private let shoulderY: CGFloat = 0.40, hipY: CGFloat = 0.62, kneeY: CGFloat = 0.80, ankleY: CGFloat = 0.95
    private let upperArm: CGFloat = 0.11, forearm: CGFloat = 0.10

    private struct Key {
        var t: Double
        var upper: Double // degrees above forward horizontal
        var fore: Double
        var knee: Double
    }

    var duration: Double { 1.0 }

    /// Full shot frames starting at `start`, including the idle lead-in and the drop back to idle.
    func frames(for style: Style, start: TimeInterval = 0) -> [PoseFrame] {
        let releaseT = 0.95
        let holdEnd = releaseT + 0.08 + style.followThroughHold
        let releaseFore = style.releaseElevation + (180 - style.releaseExtension)
        let keys = [
            Key(t: 0.0, upper: -90, fore: -80, knee: 0),
            Key(t: 0.20, upper: -60, fore: 10, knee: style.kneeForward * 0.5),
            Key(t: 0.40, upper: -30, fore: 60, knee: style.kneeForward),
            Key(t: 0.70, upper: 15, fore: 90 + style.elbowFlare, knee: style.kneeForward * 0.4),
            Key(t: releaseT, upper: style.releaseElevation, fore: releaseFore, knee: 0),
            Key(t: holdEnd, upper: style.releaseElevation, fore: releaseFore, knee: 0),
            Key(t: holdEnd + 0.45, upper: -90, fore: -80, knee: 0),
            Key(t: holdEnd + 0.70, upper: -90, fore: -80, knee: 0),
        ]
        let end = keys.last!.t
        var out: [PoseFrame] = []
        var t = 0.0
        while t <= end {
            out.append(pose(at: t, keys: keys, start: start))
            t += 1 / fps
        }
        return out
    }

    func idleFrames(seconds: Double, start: TimeInterval) -> [PoseFrame] {
        let keys = [Key(t: 0, upper: -90, fore: -80, knee: 0), Key(t: seconds, upper: -90, fore: -80, knee: 0)]
        return stride(from: 0.0, to: seconds, by: 1 / fps).map { pose(at: $0, keys: keys, start: start) }
    }

    private func pose(at t: Double, keys: [Key], start: TimeInterval) -> PoseFrame {
        let i = max(0, (keys.lastIndex { $0.t <= t } ?? 0))
        let a = keys[i], b = keys[min(i + 1, keys.count - 1)]
        let span = b.t - a.t
        let u = span > 0 ? smooth((t - a.t) / span) : 0
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * u }
        let upper = lerp(a.upper, b.upper), fore = lerp(a.fore, b.fore), kneeFwd = CGFloat(lerp(a.knee, b.knee))

        // Shooter faces +x for a right-hander filmed from their right side; mirror for lefties.
        let dir: CGFloat = handedness == .right ? 1 : -1
        let x = centerX
        let dip = kneeFwd * 0.6
        let shoulder = CGPoint(x: x, y: shoulderY + dip)
        let elbow = CGPoint(x: shoulder.x + dir * upperArm * CGFloat(cos(upper * .pi / 180)),
                            y: shoulder.y - upperArm * CGFloat(sin(upper * .pi / 180)))
        let wrist = CGPoint(x: elbow.x + dir * forearm * CGFloat(cos(fore * .pi / 180)),
                            y: elbow.y - forearm * CGFloat(sin(fore * .pi / 180)))
        let hip = CGPoint(x: x - dir * kneeFwd * 0.3, y: hipY + dip)
        let knee = CGPoint(x: x + dir * kneeFwd, y: kneeY)
        let ankle = CGPoint(x: x, y: ankleY)
        let s = handedness
        var joints: [Joint: CGPoint] = [
            .nose: CGPoint(x: x + dir * 0.02, y: 0.32 + dip),
            .neck: CGPoint(x: x, y: 0.37 + dip),
            s.shoulder: shoulder, s.elbow: elbow, s.wrist: wrist,
            s.hip: hip, s.knee: knee, s.ankle: ankle,
        ]
        // Guide arm and far-side legs, slightly offset so the skeleton reads as a body.
        let o: Handedness = s == .right ? .left : .right
        joints[o.shoulder] = CGPoint(x: shoulder.x - dir * 0.015, y: shoulder.y + 0.005)
        joints[o.elbow] = CGPoint(x: elbow.x - dir * 0.02, y: elbow.y + 0.02)
        joints[o.wrist] = CGPoint(x: wrist.x - dir * 0.035, y: wrist.y + 0.03)
        joints[o.hip] = CGPoint(x: hip.x - dir * 0.01, y: hip.y)
        joints[o.knee] = CGPoint(x: knee.x - dir * 0.015, y: knee.y)
        joints[o.ankle] = CGPoint(x: ankle.x - dir * 0.02, y: ankle.y)
        return PoseFrame(timestamp: start + t, joints: joints)
    }

    private func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
