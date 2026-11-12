import CoreGraphics
import Foundation

/// Body joints Busk uses. Coordinates are normalized image space: x right, y down, 0...1.
enum Joint: String, CaseIterable, Codable, Sendable {
    case nose, neck, root
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

enum Handedness: String, CaseIterable, Codable, Identifiable, Sendable {
    case right, left
    var id: String { rawValue }
    var label: String { self == .right ? "Right-handed" : "Left-handed" }

    var shoulder: Joint { self == .right ? .rightShoulder : .leftShoulder }
    var elbow: Joint { self == .right ? .rightElbow : .leftElbow }
    var wrist: Joint { self == .right ? .rightWrist : .leftWrist }
    var hip: Joint { self == .right ? .rightHip : .leftHip }
    var knee: Joint { self == .right ? .rightKnee : .leftKnee }
    var ankle: Joint { self == .right ? .rightAnkle : .leftAnkle }
}

/// Where the phone sits relative to the shooter.
enum CameraView: String, CaseIterable, Codable, Identifiable, Sendable {
    case side, front
    var id: String { rawValue }
    var label: String { self == .side ? "Side on" : "Facing me" }
    var hint: String {
        switch self {
        case .side: return "Phone 3-4 m away, level with your waist, looking at your shooting side. Best for arc and follow-through."
        case .front: return "Phone 3-4 m in front of you, looking straight at you. Best for elbow alignment."
        }
    }
}

/// The basketball as seen in one frame: centre in the same normalized, top-left-origin coordinates as the joints,
/// radius in image heights.
struct Ball: Sendable, Equatable {
    var center: CGPoint
    var radius: CGFloat
}

struct PoseFrame: Sendable {
    var timestamp: TimeInterval
    var joints: [Joint: CGPoint]
    /// Image width / height. Analysis multiplies x by this so angles and distances are measured in true proportions.
    var aspect: CGFloat = 1
    var ball: Ball?

    subscript(_ joint: Joint) -> CGPoint? { joints[joint] }

    /// Joint position with x scaled by the aspect ratio (units of image height). The root falls back to the hip midpoint.
    func point(_ joint: Joint) -> CGPoint? {
        guard let p = joints[joint] ?? (joint == .root ? midpoint(.leftHip, .rightHip) : nil) else { return nil }
        return CGPoint(x: p.x * aspect, y: p.y)
    }

    /// Ball centre with x scaled by the aspect ratio, like `point(_:)`.
    var ballPoint: CGPoint? { ball.map { CGPoint(x: $0.center.x * aspect, y: $0.center.y) } }

    private func midpoint(_ a: Joint, _ b: Joint) -> CGPoint? {
        guard let p = joints[a], let q = joints[b] else { return joints[a] ?? joints[b] }
        return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
    }
}

enum Geometry {
    /// Interior angle ABC in degrees.
    static func angle(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Double {
        let v1 = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let mag = hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)
        guard mag > 0 else { return 0 }
        return Double(acos(max(-1, min(1, dot / mag)))) * 180 / .pi
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }

    /// Angle of the vector a->b above the horizontal, in degrees, ignoring left/right direction (0...180 folded to 0...90 side).
    static func elevation(from a: CGPoint, to b: CGPoint) -> Double {
        let dx = Double(abs(b.x - a.x))
        let dy = Double(a.y - b.y) // y grows downward
        return atan2(dy, dx) * 180 / .pi
    }
}
