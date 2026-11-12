import CoreVideo
import ImageIO
import Vision

/// On-device body pose detection shared by the camera and video sources: follows the shooter (see `ShooterTracker`)
/// and returns joints in normalized, top-left-origin image coordinates of the upright image.
final class VisionPoseDetector {
    private let request = VNDetectHumanBodyPoseRequest()
    private let tracker = ShooterTracker()
    private let ballDetector = BallDetector()
    var minimumConfidence: Float = 0.3

    func rewind() { tracker.rewind() }

    func joints(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) -> [Joint: CGPoint]? {
        try? detect(in: pixelBuffer, orientation: orientation)
    }

    /// Throws when Vision can't run at all (the simulator has no body pose model).
    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) throws -> [Joint: CGPoint]? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        try handler.perform([request])
        return tracker.select((request.results ?? []).map { VisionPose.joints(from: $0, minConfidence: minimumConfidence) })
    }

    /// The ball in the shooter's hands on the same frame (see `BallDetector`), found from the joints `detect` returned.
    func ball(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up, joints: [Joint: CGPoint],
              at t: TimeInterval) -> Ball? {
        joints.isEmpty ? nil : ballDetector.detect(in: pixelBuffer, orientation: orientation, joints: joints, at: t)
    }
}
