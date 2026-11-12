import AVFoundation
import CoreImage
import ImageIO
import Observation

/// Plays a video file in real time and runs Vision body pose on every frame, so the whole coaching
/// pipeline can run on real footage without a camera (simulator, UI tests, debugging).
/// Launch with `-videoPath /path/to/clip.mp4`; the clip loops.
@Observable
final class VideoPoseSource: PoseSource {
    @ObservationIgnored var onFrame: ((PoseFrame) -> Void)?
    let isDemo = false
    let url: URL
    private(set) var aspectRatio: CGFloat = 9.0 / 16.0
    /// The frame currently on screen, for drawing behind the skeleton.
    private(set) var currentImage: CGImage?
    private(set) var failed = false

    @ObservationIgnored private let detector = VisionPoseDetector()
    @ObservationIgnored private let queue = DispatchQueue(label: "busk.video", qos: .userInitiated)
    @ObservationIgnored private var running = false
    @ObservationIgnored private let ciContext = CIContext()

    init(url: URL) { self.url = url }

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
        DispatchQueue.main.async { self.aspectRatio = ratio }

        let wallStart = Date()
        var last: TimeInterval = 0
        while running, let sample = output.copyNextSampleBuffer() {
            guard let pixels = CMSampleBufferGetImageBuffer(sample) else { continue }
            let t = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            last = t
            let joints = detector.joints(in: pixels, orientation: orientation) ?? [:]
            let image = ciContext.createCGImage(CIImage(cvPixelBuffer: pixels).oriented(orientation),
                                                from: CIImage(cvPixelBuffer: pixels).oriented(orientation).extent)
            let wait = t - Date().timeIntervalSince(wallStart)
            if wait > 0 { Thread.sleep(forTimeInterval: wait) }
            let frame = PoseFrame(timestamp: offset + t, joints: joints)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.running else { return }
                self.currentImage = image
                self.onFrame?(frame)
            }
        }
        reader.cancelReading()
        return last
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
