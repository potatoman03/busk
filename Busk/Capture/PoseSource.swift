import CoreGraphics
import Foundation

/// Anything that produces pose frames: the camera + Vision, or the demo shooter.
protocol PoseSource: AnyObject {
    /// Called on the main queue for each frame.
    var onFrame: ((PoseFrame) -> Void)? { get set }
    /// Aspect ratio (width / height) of the source image, for laying out the overlay.
    var aspectRatio: CGFloat { get }
    var isDemo: Bool { get }
    /// Normalized x the overlay centres on when the image is wider than the screen.
    var displayCenterX: CGFloat { get }
    func start()
    func stop()
}

extension PoseSource {
    var displayCenterX: CGFloat { 0.5 }
}

/// Replays synthetic shots on a loop so the whole app works without a camera.
final class DemoPoseSource: PoseSource {
    var onFrame: ((PoseFrame) -> Void)?
    let aspectRatio: CGFloat = 9.0 / 16.0
    let isDemo = true

    private let simulator: ShotSimulator
    private let styles: [ShotSimulator.Style]
    private let gap: Double
    private var queue: [PoseFrame] = []
    private var timer: Timer?
    private var clock: TimeInterval = 0
    private var styleIndex = 0
    private let leadIn: Double
    private var wallStart: Date?

    init(handedness: Handedness = .right, view: CameraView = .side, styles: [ShotSimulator.Style]? = nil, gap: Double = 0.8,
         leadIn: Double = 0.5) {
        var sim = ShotSimulator()
        sim.handedness = handedness
        sim.view = view
        simulator = sim
        self.styles = styles ?? ShotSimulator.Style.demoRotation(for: view)
        self.gap = gap
        self.leadIn = leadIn
    }

    func start() {
        stop()
        queue = simulator.idleFrames(seconds: leadIn, start: clock)
        wallStart = Date().addingTimeInterval(-clock)
        timer = Timer.scheduledTimer(withTimeInterval: 1 / simulator.fps, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Emits every frame that is due, so a busy main thread delays frames but never slows the replay clock.
    private func tick() {
        let now = Date().timeIntervalSince(wallStart ?? Date())
        repeat { emitNext() } while clock <= now
    }

    private func emitNext() {
        if queue.isEmpty {
            let style = styles[styleIndex % styles.count]
            styleIndex += 1
            queue = simulator.frames(for: style, start: clock) + simulator.idleFrames(seconds: gap, start: clock + 3)
            // Re-time contiguously.
            for i in queue.indices { queue[i].timestamp = clock + Double(i) / simulator.fps }
        }
        let frame = queue.removeFirst()
        clock = frame.timestamp + 1 / simulator.fps
        onFrame?(frame)
    }
}
