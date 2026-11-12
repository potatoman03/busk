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
        guard let observation = (request.results ?? []).max(by: { area($0) < area($1) }) else { return nil }
        return Self.joints(from: observation, minimumConfidence: minimumConfidence)
    }

    private func area(_ o: VNHumanBodyPoseObservation) -> CGFloat {
        guard let pts = try? o.recognizedPoints(.all).values.filter({ $0.confidence > minimumConfidence }), !pts.isEmpty else { return 0 }
        let xs = pts.map(\.location.x), ys = pts.map(\.location.y)
        return (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
    }

    static let mapping: [VNHumanBodyPoseObservation.JointName: Joint] = [
        .nose: .nose, .neck: .neck,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]

    static func joints(from o: VNHumanBodyPoseObservation, minimumConfidence: Float = 0.3) -> [Joint: CGPoint] {
        guard let points = try? o.recognizedPoints(.all) else { return [:] }
        var out: [Joint: CGPoint] = [:]
        for (name, joint) in mapping {
            guard let p = points[name], p.confidence > minimumConfidence else { continue }
            out[joint] = CGPoint(x: p.location.x, y: 1 - p.location.y)
        }
        return out
    }
}
