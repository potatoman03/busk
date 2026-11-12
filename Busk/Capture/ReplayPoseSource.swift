import CoreGraphics
import Foundation

/// Replays a recorded keypoint sequence (the shot benchmark's `busk-bench-keypoints/1` sidecar) through the live
/// session, so busk analyses and coaches a known clip on screen. Simulator and benchmark use only.
final class ReplayPoseSource: PoseSource {
    struct Clip {
        var fps: Double
        var view: CameraView
        var handedness: Handedness
        var aspectRatio: CGFloat
        var frames: [[Joint: CGPoint]]
    }

    var onFrame: ((PoseFrame) -> Void)?
    var aspectRatio: CGFloat { clip.aspectRatio }
    /// Benchmark clips are landscape; keep the shooter on screen instead of the frame's centre.
    var displayCenterX: CGFloat {
        let xs = clip.frames.flatMap { $0.values.map(\.x) }
        return xs.isEmpty ? 0.5 : xs.reduce(0, +) / CGFloat(xs.count)
    }
    let isDemo = true
    let clip: Clip

    private var index = 0
    private var timer: Timer?
    /// Called once on the main thread after every clip frame (and the hold) has gone through the session.
    var onFinished: (() -> Void)?
    /// Clip frames delivered so far (the hold frames are not counted).
    private(set) var framesPlayed = 0
    /// Frames to keep showing the last pose after the clip ends, so a follow-through still in progress can finish.
    private var holdFrames: Int { Int(clip.fps * 1.5) }

    init(clip: Clip) {
        self.clip = clip
    }

    convenience init(contentsOf url: URL) throws {
        self.init(clip: try Self.parse(Data(contentsOf: url)))
    }

    static func parse(_ data: Data) throws -> Clip {
        guard let doc = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let raw = doc["frames"] as? [[String: Any]], !raw.isEmpty else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let width = doc["width"] as? Double ?? 9, height = doc["height"] as? Double ?? 16
        let frames = raw.map { f in
            var joints: [Joint: CGPoint] = [:]
            for (name, v) in (f["joints"] as? [String: Any]) ?? [:] {
                guard let joint = joint(snakeCase: name), let xy = v as? [Double], xy.count >= 2 else { continue }
                joints[joint] = CGPoint(x: xy[0], y: xy[1])
            }
            return joints
        }
        return Clip(fps: doc["fps"] as? Double ?? 30,
                    view: CameraView(rawValue: doc["view"] as? String ?? "") ?? .side,
                    handedness: Handedness(rawValue: doc["handedness"] as? String ?? "") ?? .right,
                    aspectRatio: CGFloat(width / height), frames: frames)
    }

    static func joint(snakeCase name: String) -> Joint? {
        let parts = name.split(separator: "_")
        guard let first = parts.first else { return nil }
        return Joint(rawValue: String(first) + parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined())
    }

    func start() {
        stop()
        index = 0
        framesPlayed = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1 / clip.fps, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        guard index < clip.frames.count + holdFrames else {
            stop()
            onFinished?()
            onFinished = nil
            return
        }
        let joints = clip.frames[min(index, clip.frames.count - 1)]
        onFrame?(PoseFrame(timestamp: Double(index) / clip.fps, joints: joints))
        if index < clip.frames.count { framesPlayed = index + 1 }
        index += 1
    }
}
