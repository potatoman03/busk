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
        var releaseMinElbowAngle: Double = 130
        var gatherMaxElbowAngle: Double = 130
        /// Seconds of motion kept before the release.
        var lookback: TimeInterval = 2.0
        /// Seconds after the release before the shot is measured (lets the landing happen).
        var settle: TimeInterval = 0.9
        var maxFollowThrough: TimeInterval = 1.5
        /// Wrist speed (body heights / s) below which the ball counts as stopped.
        var pauseSpeed: Double = 0.08
        /// How far (body heights) the hand can wander and still count as stopped at the set point.
        var pauseRadius: Double = 0.02
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
        var guide: CGPoint?, guideShoulder: CGPoint?, root: CGPoint?, ankle: CGPoint?
        var span: Double? // nose-to-ankle height
    }

    private func measure(release rt: TimeInterval) -> ShotMetrics? {
        // Facing the camera, Vision sometimes swaps left and right for a frame. Trust the shoulder order most frames show.
        let order = { (f: PoseFrame) -> CGFloat? in
            guard let r = f.point(.rightShoulder), let l = f.point(.leftShoulder), abs(r.x - l.x) > 0.01 else { return nil }
            return r.x - l.x
        }
        let window = history.filter { $0.timestamp >= rt - config.lookback }
        // Only this shot's frames vote: a pose left over from before (a held frame, the last shot) can't flip it.
        let usual = view == .front ? window.compactMap(order).reduce(0) { $0 + ($1 > 0 ? 1 : -1) } : 0
        let all: [Sample] = window.compactMap { f in
            let flipped = usual != 0 && order(f).map { ($0 > 0) != (usual > 0) } == true
            let hand: Handedness = flipped ? (handedness == .right ? .left : .right) : handedness
            let guideSide: Handedness = hand == .right ? .left : .right
            guard let s = f.point(hand.shoulder), let e = f.point(hand.elbow), let w = f.point(hand.wrist),
                  let head = f.point(.nose) ?? f.point(.neck) else { return nil }
            let ankles = [f.point(.leftAnkle), f.point(.rightAnkle)].compactMap { $0 }
            let ankle = ankles.isEmpty ? nil : CGPoint(x: ankles.map(\.x).reduce(0, +) / CGFloat(ankles.count),
                                                       y: ankles.map(\.y).reduce(0, +) / CGFloat(ankles.count))
            return Sample(t: f.timestamp, shoulder: s, elbow: e, wrist: w, head: head, guide: f.point(guideSide.wrist), guideShoulder: f.point(guideSide.shoulder),
                          root: f.point(.root), ankle: ankle, span: ankle.map { Double($0.y - head.y) })
        }
        // Only the motion since the last break in the frames counts (a looping video or a dropped stretch of frames
        // would otherwise mix in a pose from somewhere else).
        let cut = all.indices.last { $0 > 0 && all[$0].t - all[$0 - 1].t > 0.3 && all[$0].t <= rt } ?? 0
        let samples = Array(all[cut...])
        guard samples.count >= 8 else { return nil }
        let n = samples.count
        let gaps = zip(samples.dropFirst(), samples).map { $0.t - $1.t }.sorted()
        let dt = max(gaps[gaps.count / 2], 1.0 / 120)

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
        // Go back up the push to its fastest frame, then down to where the hand slowed; a dip that is still more
        // than half as fast as the push is jitter within it, so keep going.
        var setIdx = max(lo, rel - 1)
        var pushSpeed = 0.0
        while true {
            while setIdx > lo && speed[setIdx - 1] >= speed[setIdx] { setIdx -= 1 }
            pushSpeed = max(pushSpeed, speed[setIdx])
            while setIdx > lo && speed[setIdx - 1] <= speed[setIdx] { setIdx -= 1 }
            if setIdx <= lo || speed[setIdx] < pushSpeed * 0.5 { break }
        }
        // The pause: the longest stretch the hand stays put (within a radius, so pose jitter during a long hold doesn't
        // cut it short) with the ball up at the set point (or as high as it gets on a low set), wherever in the gather.
        let hand = { (i: Int) in CGPoint(x: samples[i].wrist.x - samples[i].shoulder.x, y: samples[i].wrist.y - samples[i].shoulder.y) }
        let setLift = max(lift(setIdx) - 0.05, -0.15) // never a hold down at the waist
        var hitch = 0.0
        for a in lo..<rel where lift(a) > 0 || lift(a) >= setLift {
            var b = a
            while b + 1 < rel && Double(hypot(hand(b + 1).x - hand(a).x, hand(b + 1).y - hand(a).y)) / H < config.pauseRadius { b += 1 }
            hitch = max(hitch, Double(b - a + 1) * dt)
        }
        let set = samples[setIdx]
        var setPointHeight = Double(set.shoulder.y - set.wrist.y) / H
        if view == .front, lift(setIdx) <= (lo..<rel).map(lift).min()! + 0.03 {
            // From the front, a ball carried up toward the camera without stopping hides the set point, so the slowest
            // frame is the bottom of the dip. The ball is loaded where the elbow bends most with the wrist above it.
            let bend = { (i: Int) in Geometry.angle(samples[i].shoulder, samples[i].elbow, samples[i].wrist) }
            if let loaded = (setIdx..<rel).filter({ samples[$0].wrist.y < samples[$0].elbow.y }).min(by: { bend($0) < bend($1) }) {
                setPointHeight = max(setPointHeight, lift(loaded))
            }
        }

        // Elbow: sideways elbow-to-wrist offset over the third of a second before the release (the median, so one
        // frame where the forearm is turned toward the camera doesn't count as a flare).
        var elbowFlare: Double?
        if view == .front {
            let offsets = samples[..<rel].filter { $0.t >= samples[rel].t - 0.34 }.map { Double(abs($0.elbow.x - $0.wrist.x)) / H }.sorted()
            elbowFlare = offsets.isEmpty ? Double(abs(set.elbow.x - set.wrist.x)) / H : offsets[offsets.count / 2]
        }

        // Arc: the arm's elevation while it is fully extended at the release (earlier frames still show the set point).
        var armAngle: Double?
        if view == .side {
            let window = Array(max(0, rel - 2)...min(n - 1, rel + 4))
            let reach = { (i: Int) in Geometry.distance(samples[i].shoulder, samples[i].wrist) }
            let longest = window.map(reach).max() ?? 0
            let extended = window.filter { reach($0) >= longest * 0.97 }
                .map { Geometry.elevation(from: samples[$0].shoulder, to: samples[$0].wrist) }.sorted()
            armAngle = extended.isEmpty ? nil : extended[extended.count / 2]
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
            // Off the floor: a fifth of the way up the jump, so slow drift of the feet in the frame isn't counted as air time.
            // The floor is measured near the jump: the shooter can step or the camera tilt elsewhere in the clip.
            let reach = Int(0.8 / dt)
            let floor0 = (max(firstFoot, top - reach)...top).compactMap { feet[$0] }.min() ?? feet[firstFoot]!
            let floor1 = (top...min(lastFoot, top + reach)).compactMap { feet[$0] }.min() ?? feet[lastFoot]!
            let level0 = floor0 + max(0.012, (feet[top]! - floor0) * 0.2)
            let level1 = floor1 + max(0.012, (feet[top]! - floor1) * 0.2)
            var s0 = top, s1 = top
            while s0 > 0, let f = feet[s0 - 1], f > level0 { s0 -= 1 }
            while s1 < n - 1, let f = feet[s1 + 1], f > level1 { s1 += 1 }
            let air = s1 - s0 + 1
            if air >= 3, rel >= s0 - 2, rel <= s1 + 2 {
                // Sub-frame peak and takeoff/landing times: a short jump is only a few frames long.
                // The hips trace the jump's arc; feet tuck in the air and peak early.
                let hips = samples.map { s in s.root.map { -Double($0.y) / H } }
                let peakIdx = (s0...s1).filter { hips[$0] != nil }.max { hips[$0]! < hips[$1]! } ?? top
                var apex = samples[peakIdx].t
                if peakIdx > 0, peakIdx < n - 1, let a = hips[peakIdx - 1], let b = hips[peakIdx], let c = hips[peakIdx + 1],
                   a - 2 * b + c < 0 {
                    apex += (a - c) / (2 * (a - 2 * b + c)) * dt
                }
                func crossing(_ i: Int, _ j: Int, _ level: Double) -> Double? {
                    guard i >= 0, j < n, let fi = feet[i], let fj = feet[j], fi != fj else { return nil }
                    return samples[i].t + (level - fi) / (fj - fi) * (samples[j].t - samples[i].t)
                }
                let up = crossing(s0 - 1, s0, level0) ?? samples[s0].t
                let down = crossing(s1, s1 + 1, level1) ?? samples[s1].t
                releaseTiming = (samples[rel].t - apex) / max((down - up) / 2, dt)
                let takeoff = samples[..<s0].last { $0.ankle != nil } ?? samples[firstFoot]
                let settled = samples.last { $0.ankle != nil && $0.t <= samples[s1].t + 0.6 } ?? samples[lastFoot]
                if let a0 = takeoff.ankle, let a1 = settled.ankle {
                    var d = Double(abs(a1.x - a0.x)) / H
                    if view == .front, let h0 = takeoff.span, let h1 = settled.span, h1 > 0 {
                        d = max(d, abs(1 - h0 / h1) * 3.1) // getting bigger or smaller = moving toward or away from the camera
                    } else if view == .side {
                        // From the side, drifting toward or away from the camera only shows as a change in size. The torso
                        // keeps its length through the jump (the head and legs don't), so compare it before and after.
                        func torso(_ s: ArraySlice<Sample>) -> Double? {
                            let lengths = s.compactMap { x in x.root.map { Geometry.distance(x.shoulder, $0) } }.sorted()
                            return lengths.isEmpty ? nil : lengths[lengths.count / 2]
                        }
                        let after = samples.indices.filter { samples[$0].t >= samples[s1].t + 0.35 && samples[$0].t <= samples[s1].t + 0.65 }
                        if let t0 = torso(samples[max(0, s0 - 4)..<s0]), let first = after.first, let last = after.last,
                           let t1 = torso(samples[first...last]), t1 > 0 {
                            d = max(d, abs(1 - t0 / t1) * 3.1)
                        }
                    }
                    drift = d
                }
            }
        }

        var guideHandPush: Double?
        if view == .front, rel + 4 < n, let g0 = samples[rel].guide, let g1 = samples[rel + 4].guide,
           let r0 = samples[rel].root, let r1 = samples[rel + 4].root {
            // Only travel toward the shooting hand is a push; a guide hand dropping or peeling away is a clean release.
            let toward: CGFloat = samples[rel].wrist.x >= g0.x ? 1 : -1
            guideHandPush = max(0, Double(((g1.x - g0.x) - (r1.x - r0.x)) * toward)) / H
        }

        return ShotMetrics(view: view, setPointHeight: setPointHeight, elbowFlare: elbowFlare, armAngle: armAngle,
                           followThrough: followThrough, legDrive: legDrive, releaseTiming: releaseTiming,
                           hitch: hitch, drift: drift, guideHandPush: guideHandPush)
    }
}
