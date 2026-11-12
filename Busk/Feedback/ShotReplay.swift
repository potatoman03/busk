import CoreGraphics
import Foundation

/// The instant replay shown after a shot: this shot's skeleton with the session's best earlier shot laid over it as a
/// ghost, both lined up at the release. Points are in aspect-corrected image units (`PoseFrame.point`).
struct ShotReplay: Identifiable {
    struct Track {
        /// Seconds relative to the release, ascending.
        var times: [TimeInterval]
        var poses: [[Joint: CGPoint]]
        var number: Int
        var score: Int

        /// The pose on screen `t` seconds after the release (before it when negative); holds the ends.
        func pose(at t: TimeInterval) -> [Joint: CGPoint] {
            guard let i = times.lastIndex(where: { $0 <= t }) else { return poses.first ?? [:] }
            return poses[i]
        }
    }

    /// Seconds of motion shown before and after the release.
    static let before: TimeInterval = 1.0
    static let after: TimeInterval = 0.8

    let id = UUID()
    let shot: Track
    let ghost: Track?
    /// Area covering both skeletons over the whole replay, to zoom the replay on the body.
    let bounds: CGRect

    var isNewBest: Bool { ghost.map { shot.score > $0.score } ?? true }

    init(shot clip: ShotClip, number: Int, score: Int, best: (clip: ShotClip, number: Int, score: Int)?) {
        let shot = Self.track(clip, number: number, score: score)
        self.shot = shot
        ghost = best.map { b in Self.aligned(Self.track(b.clip, number: b.number, score: b.score), to: shot) }
        let points = ([shot] + (ghost.map { [$0] } ?? [])).flatMap { $0.poses.flatMap(\.values) }
        bounds = points.isEmpty ? CGRect(x: 0, y: 0, width: 1, height: 1) : points.dropFirst().reduce(
            CGRect(origin: points[0], size: .zero)) { $0.union(CGRect(origin: $1, size: .zero)) }
    }

    private static func track(_ clip: ShotClip, number: Int, score: Int) -> Track {
        let frames = clip.frames.filter { $0.timestamp >= clip.release - before - 0.1 && $0.timestamp <= clip.release + after + 0.1 }
        return Track(times: frames.map { $0.timestamp - clip.release },
                     poses: frames.map { f in Dictionary(uniqueKeysWithValues: f.joints.keys.compactMap { j in f.point(j).map { (j, $0) } }) },
                     number: number, score: score)
    }

    /// Moves and scales the ghost so its body sits where this shot's body is at the release.
    static func aligned(_ ghost: Track, to shot: Track) -> Track {
        let a = shot.pose(at: 0), b = ghost.pose(at: 0)
        guard let pa = anchor(a), let pb = anchor(b) else { return ghost }
        let scale = torso(a).flatMap { ta in torso(b).map { tb in tb > 0 ? min(1.5, max(0.67, ta / tb)) : 1 } } ?? 1
        var out = ghost
        out.poses = ghost.poses.map { pose in
            pose.mapValues { CGPoint(x: pa.x + ($0.x - pb.x) * scale, y: pa.y + ($0.y - pb.y) * scale) }
        }
        return out
    }

    private static func mid(_ p: [Joint: CGPoint], _ a: Joint, _ b: Joint) -> CGPoint? {
        guard let x = p[a], let y = p[b] else { return p[a] ?? p[b] }
        return CGPoint(x: (x.x + y.x) / 2, y: (x.y + y.y) / 2)
    }

    private static func anchor(_ p: [Joint: CGPoint]) -> CGPoint? {
        p[.root] ?? mid(p, .leftHip, .rightHip) ?? p[.neck] ?? mid(p, .leftShoulder, .rightShoulder)
    }

    private static func torso(_ p: [Joint: CGPoint]) -> CGFloat? {
        guard let s = mid(p, .leftShoulder, .rightShoulder), let h = p[.root] ?? mid(p, .leftHip, .rightHip) else { return nil }
        return hypot(s.x - h.x, s.y - h.y)
    }
}
