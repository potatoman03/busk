import CoreVideo
import ImageIO
import Vision

/// On-device body pose detection shared by the camera and video sources: picks the largest person in frame
/// and returns joints in normalized, top-left-origin image coordinates of the upright image.
final class VisionPoseDetector {
    private let request = VNDetectHumanBodyPoseRequest()
    var minimumConfidence: Float = 0.3

    func joints(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) -> [Joint: CGPoint]? {
        try? detect(in: pixelBuffer, orientation: orientation)
    }

    /// Throws when Vision can't run at all (the simulator has no body pose model).
    func detect(in pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up) throws -> [Joint: CGPoint]? {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        try handler.perform([request])
        guard let observation = VisionPose.largest(request.results ?? []) else { return nil }
        return VisionPose.joints(from: observation, minConfidence: minimumConfidence)
    }
}
