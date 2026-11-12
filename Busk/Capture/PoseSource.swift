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

    init(handedness: Handedness = .right, styles: [ShotSimulator.Style] = ShotSimulator.Style.demoRotation, gap: Double = 0.8) {
        var sim = ShotSimulator()
        sim.handedness = handedness
        simulator = sim
        self.styles = styles
        self.gap = gap
    }

    func start() {
        stop()
        queue = simulator.idleFrames(seconds: 0.5, start: clock)
        timer = Timer.scheduledTimer(withTimeInterval: 1 / simulator.fps, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        if queue.isEmpty {
            let style = styles[styleIndex % styles.count]
            styleIndex += 1
            queue = simulator.frames(for: style, start: clock) + simulator.idleFrames(seconds: gap, start: clock + 2.5)
            // Re-time contiguously.
            for i in queue.indices { queue[i].timestamp = clock + Double(i) / simulator.fps }
        }
        let frame = queue.removeFirst()
        clock = frame.timestamp + 1 / simulator.fps
        onFrame?(frame)
    }
}
