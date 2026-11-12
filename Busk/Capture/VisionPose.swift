import CoreGraphics
import Vision

/// Converts Apple Vision body-pose observations into Busk joints (top-left origin, y down).
enum VisionPose {
    static let mapping: [VNHumanBodyPoseObservation.JointName: Joint] = [
        .nose: .nose, .neck: .neck, .root: .root,
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]

    static func joints(from o: VNHumanBodyPoseObservation, minConfidence: Float = 0.3) -> [Joint: CGPoint] {
        guard let points = try? o.recognizedPoints(.all) else { return [:] }
        var out: [Joint: CGPoint] = [:]
        for (name, joint) in mapping {
            guard let p = points[name], p.confidence > minConfidence else { continue }
            out[joint] = CGPoint(x: p.location.x, y: 1 - p.location.y)
        }
        return out
    }

    /// The person filling the most of the frame: the shooter, not someone in the background.
    static func largest(_ observations: [VNHumanBodyPoseObservation]) -> VNHumanBodyPoseObservation? {
        observations.max { area($0) < area($1) }
    }

    static func area(_ o: VNHumanBodyPoseObservation) -> CGFloat {
        guard let pts = try? o.recognizedPoints(.all).values.filter({ $0.confidence > 0.3 }), !pts.isEmpty else { return 0 }
        let xs = pts.map(\.location.x), ys = pts.map(\.location.y)
        return (xs.max()! - xs.min()!) * (ys.max()! - ys.min()!)
    }
}
