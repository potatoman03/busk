import CoreGraphics
import Foundation

/// Generates synthetic pose sequences of a jump shot, filmed from the side or the front.
/// Drives demo mode (simulator, UI tests) and unit tests.
struct ShotSimulator {
    struct Style: Equatable {
        var name: String
        /// Elbow tilt out from under the ball at the set point, degrees (seen from the front).
        var elbowFlare: Double = 0
        /// Upper-arm elevation at release, degrees above horizontal.
        var releaseElevation: Double = 65
        /// Elbow interior angle at release.
        var releaseExtension: Double = 172
        /// Seconds the hand stays up after release.
        var followThroughHold: Double = 0.68
        /// How far the knee travels forward in the dip (normalized). ~0.06 is a good bend.
        var kneeForward: Double = 0.06
        /// Upper-arm and forearm elevation at the set point. The default puts the ball above the forehead.
        var setUpper: Double = 15
        var setFore: Double = 90
        /// Seconds the ball stops at the set point.
        var hitch: Double = 0
        /// Seconds after the top of the jump that the ball leaves the hand.
        var releaseDelay: Double = 0
        /// Distance the body travels in the air (normalized; negative = fading back or away).
        var drift: Double = 0
        /// The guide hand shoves the ball at release.
        var guidePush = false

        static let good = Style(name: "Good form")
        static let lowSet = Style(name: "Chest push", setUpper: -40, setFore: 30)
        static let flaredElbow = Style(name: "Flared elbow", elbowFlare: 50)
        static let flat = Style(name: "Flat shot", releaseElevation: 30, releaseExtension: 168)
        static let noFollowThrough = Style(name: "No follow-through", followThroughHold: 0)
        static let stiffLegs = Style(name: "Stiff legs", kneeForward: 0.01)
        static let hitched = Style(name: "Hitch", hitch: 0.3)
        static let fader = Style(name: "Fading away", releaseDelay: 0.03, drift: -0.15)
        static let lateRelease = Style(name: "Late release", releaseDelay: 0.24)
        static let guideThumb = Style(name: "Guide-hand push", guidePush: true)

        /// A demo session: one shot per flaw the camera angle can show, between good shots.
        static func demoRotation(for view: CameraView) -> [Style] {
            view == .side
                ? [.good, .lowSet, .flat, .hitched, .fader, .lateRelease, .noFollowThrough, .stiffLegs, .good]
                : [.good, .flaredElbow, .guideThumb, .lowSet, .hitched, .fader, .lateRelease, .noFollowThrough, .good]
        }
    }

    var fps: Double = 30
    var handedness: Handedness = .right
    var view: CameraView = .side
    /// Horizontal position of the shooter in the frame.
    var centerX: CGFloat = 0.5

    private let shoulderY: CGFloat = 0.40, hipY: CGFloat = 0.62, kneeY: CGFloat = 0.80, ankleY: CGFloat = 0.95
    private let upperArm: CGFloat = 0.11, forearm: CGFloat = 0.10
    private let jumpHeight = 0.05, halfAir = 0.2

    private struct Key {
        var t: Double
        var upper: Double // degrees above forward horizontal
        var fore: Double
        var knee: Double
        var flare: Double = 0
    }

    /// Full shot frames starting at `start`, including the idle lead-in and the drop back to idle.
    func frames(for style: Style, start: TimeInterval = 0) -> [PoseFrame] {
        let apex = 0.95 + style.hitch
        let releaseT = apex + style.releaseDelay
        let holdEnd = releaseT + style.followThroughHold
        let releaseFore = style.releaseElevation + (180 - style.releaseExtension)
        let set = Key(t: 0.70 + style.releaseDelay, upper: style.setUpper, fore: style.setFore, knee: style.kneeForward * 0.4, flare: style.elbowFlare)
        var keys = [
            Key(t: 0.0, upper: -90, fore: -80, knee: 0),
            Key(t: 0.20, upper: -60, fore: 10, knee: style.kneeForward * 0.5),
            Key(t: 0.40, upper: -30, fore: 60, knee: style.kneeForward),
            set,
        ]
        if style.hitch > 0 { var held = set; held.t += style.hitch; keys.append(held) }
        keys += [
            Key(t: releaseT, upper: style.releaseElevation, fore: releaseFore, knee: 0),
            Key(t: holdEnd, upper: style.releaseElevation, fore: releaseFore, knee: 0),
            Key(t: holdEnd + 0.3, upper: -90, fore: -80, knee: 0),
            Key(t: max(holdEnd + 0.70, apex + halfAir + 0.5), upper: -90, fore: -80, knee: 0),
        ]
        let end = keys.last!.t
        return stride(from: 0.0, through: end, by: 1 / fps).map { t in
            let air = max(0, 1 - pow((t - apex) / halfAir, 2))
            let travel = min(1, max(0, (t - (apex - halfAir)) / (2 * halfAir)))
            let push = style.guidePush ? min(1, max(0, (t - releaseT) / 0.12)) : 0
            return pose(at: t, keys: keys, start: start, lift: jumpHeight * air, shift: style.drift * travel, guidePush: push)
        }
    }

    func idleFrames(seconds: Double, start: TimeInterval) -> [PoseFrame] {
        let keys = [Key(t: 0, upper: -90, fore: -80, knee: 0), Key(t: seconds, upper: -90, fore: -80, knee: 0)]
        return stride(from: 0.0, to: seconds, by: 1 / fps).map { pose(at: $0, keys: keys, start: start, lift: 0, shift: 0, guidePush: 0) }
    }

    private func pose(at t: Double, keys: [Key], start: TimeInterval, lift: Double, shift: Double, guidePush: Double) -> PoseFrame {
        let i = max(0, (keys.lastIndex { $0.t <= t } ?? 0))
        let a = keys[i], b = keys[min(i + 1, keys.count - 1)]
        let span = b.t - a.t
        let u = span > 0 ? smooth((t - a.t) / span) : 0
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * u }
        let upper = lerp(a.upper, b.upper), fore = lerp(a.fore, b.fore), kneeFwd = CGFloat(lerp(a.knee, b.knee))
        let flare = lerp(a.flare, b.flare)

        // Side: the shooter faces +x for a right-hander filmed from their right side. Front: the shooter faces the camera,
        // so forward/back is invisible and their right side is on the image's left. Lefties are mirrored.
        let dir: CGFloat = handedness == .right ? 1 : -1
        let side = view == .side
        let up = CGFloat(-lift), dip = kneeFwd * 0.6
        let x = centerX + CGFloat(shift)
        let shoulderX = side ? x : x - dir * 0.06
        let shoulder = CGPoint(x: shoulderX, y: shoulderY + dip + up)
        let elbowFwd = upperArm * CGFloat(cos(upper * .pi / 180)), wristFwd = forearm * CGFloat(cos(fore * .pi / 180))
        let elbowY = shoulder.y - upperArm * CGFloat(sin(upper * .pi / 180))
        let wristY = elbowY - forearm * CGFloat(sin(fore * .pi / 180))
        let elbow: CGPoint, wrist: CGPoint
        if side {
            elbow = CGPoint(x: shoulder.x + dir * elbowFwd, y: elbowY)
            wrist = CGPoint(x: elbow.x + dir * wristFwd, y: wristY)
        } else {
            wrist = CGPoint(x: shoulder.x + dir * 0.02, y: wristY)
            elbow = CGPoint(x: wrist.x - dir * (0.01 + 0.1 * CGFloat(sin(flare * .pi / 180))), y: elbowY)
        }
        let hip = CGPoint(x: side ? x - dir * kneeFwd * 0.3 : x - dir * 0.04, y: hipY + dip + up)
        let knee = CGPoint(x: side ? x + dir * kneeFwd : x - dir * 0.045, y: kneeY + up)
        let ankle = CGPoint(x: side ? x : x - dir * 0.045, y: ankleY + up)
        let s = handedness
        var joints: [Joint: CGPoint] = [
            .nose: CGPoint(x: x + (side ? dir * 0.02 : 0), y: 0.32 + dip + up),
            .neck: CGPoint(x: x, y: 0.37 + dip + up),
            s.shoulder: shoulder, s.elbow: elbow, s.wrist: wrist,
            s.hip: hip, s.knee: knee, s.ankle: ankle,
        ]
        // Guide arm and far-side legs. The guide hand rests on the side of the ball; a push shoves it through the ball.
        let o: Handedness = s == .right ? .left : .right
        let mirror = { (p: CGPoint) in CGPoint(x: 2 * x - p.x, y: p.y) }
        let shove = CGFloat(guidePush)
        if side {
            joints[o.shoulder] = CGPoint(x: shoulder.x - dir * 0.015, y: shoulder.y + 0.005)
            joints[o.elbow] = CGPoint(x: elbow.x - dir * 0.02, y: elbow.y + 0.02)
            joints[o.wrist] = CGPoint(x: wrist.x - dir * 0.035 + dir * 0.05 * shove, y: wrist.y + 0.03 - 0.03 * shove)
            joints[o.hip] = CGPoint(x: hip.x - dir * 0.01, y: hip.y)
            joints[o.knee] = CGPoint(x: knee.x - dir * 0.015, y: knee.y)
            joints[o.ankle] = CGPoint(x: ankle.x - dir * 0.02, y: ankle.y)
        } else {
            joints[o.shoulder] = mirror(shoulder)
            joints[o.wrist] = CGPoint(x: wrist.x + dir * (0.06 - 0.07 * shove), y: wrist.y + 0.01 - 0.05 * shove)
            joints[o.elbow] = CGPoint(x: joints[o.shoulder]!.x + dir * 0.02, y: (shoulder.y + joints[o.wrist]!.y) / 2 + 0.03)
            joints[o.hip] = mirror(hip)
            joints[o.knee] = mirror(knee)
            joints[o.ankle] = mirror(ankle)
        }
        return PoseFrame(timestamp: start + t, joints: joints)
    }

    private func smooth(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
