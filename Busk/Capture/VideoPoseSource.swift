import AVFoundation
import CoreImage
import ImageIO
import Observation

/// Plays a video file in real time and runs Vision body pose on every frame, so the whole coaching
/// pipeline can run on real footage without a camera (simulator, UI tests, debugging).
/// Launch with `-videoPath /path/to/clip.mp4`; the clip loops. The simulator has no body pose model, so there a
/// `busk-bench-keypoints/1` sidecar (`CLIP.keypoints.json`, from `scripts/vision-keypoints.swift`) supplies the pose.

@Observable
final class VideoPoseSource: PoseSource {
    @ObservationIgnored var onFrame: ((PoseFrame) -> Void)?
    let isDemo = false
    let url: URL
    private(set) var aspectRatio: CGFloat = 9.0 / 16.0
    private var poseAspect: CGFloat = 9.0 / 16.0
    /// The frame currently on screen, for drawing behind the skeleton.
    private(set) var currentImage: CGImage?
    /// The pose of the frame in `currentImage`; when drawing falls behind, the analysed pose runs ahead of the picture.
    private(set) var currentImagePose: PoseFrame?
    private(set) var failed = false
    /// Pose comes from a keypoints sidecar rather than live Vision.
    let keypoints: ReplayPoseSource.Clip?
    private(set) var visionUnavailable = false

    @ObservationIgnored private let detector = VisionPoseDetector()
    @ObservationIgnored private let queue = DispatchQueue(label: "busk.video", qos: .userInitiated)
    @ObservationIgnored private var running = false
    @ObservationIgnored private var lastJoints: [Joint: CGPoint]?
    @ObservationIgnored private let ciContext = CIContext()

    init(url: URL, keypointsURL: URL? = nil) {
        self.url = url
        let sidecar = keypointsURL ?? url.deletingPathExtension().appendingPathExtension("keypoints.json")
        keypoints = (try? Data(contentsOf: sidecar)).flatMap { try? ReplayPoseSource.parse($0) }
    }

    func start() {
        guard !running else { return }
        running = true
        queue.async { [weak self] in self?.playLoop() }
    }

    func stop() { running = false }

    private func playLoop() {
        var offset: TimeInterval = 0
        while running {
            guard let played = playOnce(offset: offset), played > 0 else {
                DispatchQueue.main.async { self.failed = true }
                return
            }
            offset += played + 1
        }
    }

    /// Returns the clip duration played, or nil if the file can't be read.
    private func playOnce(offset: TimeInterval) -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first,
              let reader = try? AVAssetReader(asset: asset) else { return nil }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return nil }
        reader.add(output)
        guard reader.startReading() else { return nil }

        let orientation = Self.orientation(for: track.preferredTransform)
        let size = track.naturalSize.applying(track.preferredTransform)
        let ratio = abs(size.width) / max(abs(size.height), 1)
        poseAspect = ratio
        DispatchQueue.main.async { self.aspectRatio = ratio }

        let wallStart = Date()
        var last: TimeInterval = 0
        var lastDrawn: TimeInterval?
        while running, let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            last = t
            let joints = pose(at: t, pixels: pixels, orientation: orientation)
            if !joints.isEmpty { lastJoints = joints }
            let behind = Date().timeIntervalSince(wallStart) - t > Self.maxLag
            let draw = Self.shouldDraw(at: t, behind: behind, lastDrawn: lastDrawn)
            if draw { lastDrawn = t }
            let image = draw ? displayImage(pixels, orientation: orientation) : nil
            let wait = t - Date().timeIntervalSince(wallStart)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            let frame = PoseFrame(timestamp: offset + t, joints: joints, aspect: poseAspect)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running else { return }
                if let image {
                    self.currentImage = image
                    // Bridge single dropped detections so the skeleton doesn't flicker, but never draw a stale body.
                    if !frame.joints.isEmpty || (self.currentImagePose.map { frame.timestamp - $0.timestamp > Self.bridgeSeconds } ?? true) {
                        self.currentImagePose = frame
                    }
                }
                self.onFrame?(frame)
            }
        }
        reader.cancelReading()
        holdLastPose(after: offset + last, wallStart: wallStart, clipEnd: last)
        return last + Self.holdSeconds
    }

    /// Frames this far behind real time skip drawing (pose still goes through) so playback keeps up.
    private static let maxLag: TimeInterval = 0.1
    /// Even when live Vision keeps playback behind on every frame, the picture still updates this often.
    static let minDrawInterval: TimeInterval = 0.2
    /// A drawn frame with no detection keeps the last body this long; covers one missed detection at `minDrawInterval`.
    static let bridgeSeconds: TimeInterval = 0.3

    static func shouldDraw(at t: TimeInterval, behind: Bool, lastDrawn: TimeInterval?) -> Bool {
        guard behind, let lastDrawn else { return true }
        return t - lastDrawn >= minDrawInterval
    }
    /// Longest side of the background image; full-size CoreImage renders are too slow to keep up in the simulator.
    private static let displayMaxSide: CGFloat = 720

    private func displayImage(_ pixels: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CGImage? {
        let oriented = CIImage(cvPixelBuffer: pixels).oriented(orientation)
        let scale = min(1, Self.displayMaxSide / max(oriented.extent.width, oriented.extent.height))
        let scaled = oriented.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return ciContext.createCGImage(scaled, from: scaled.extent)
    }

    /// Keeps the final pose on screen briefly so a follow-through still in progress when the clip ends can finish.
    private static let holdSeconds = 1.5

    private func holdLastPose(after t0: TimeInterval, wallStart: Date, clipEnd: TimeInterval) {
        guard let joints = lastJoints else { return }
        let step = 1.0 / 30
        var t = step
        while running, t <= Self.holdSeconds {
            let wait = clipEnd + t - Date().timeIntervalSince(wallStart)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            let frame = PoseFrame(timestamp: t0 + t, joints: joints, aspect: poseAspect)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running else { return }
                self.onFrame?(frame)
            }
            t += step
        }
    }

    private func pose(at t: TimeInterval, pixels: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> [Joint: CGPoint] {
        if let clip = keypoints, !clip.frames.isEmpty {
            return clip.frames[min(max(Int((t * clip.fps).rounded()), 0), clip.frames.count - 1)]
        }
        do {
            return try detector.detect(in: pixels, orientation: orientation) ?? [:]
        } catch {
            if !visionUnavailable { DispatchQueue.main.async { self.visionUnavailable = true } }
            return [:]
        }
    }

    static func orientation(for t: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (t.a, t.b, t.c, t.d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }
}
