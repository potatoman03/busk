import CoreGraphics
import Foundation

/// Body joints Busk uses. Coordinates are normalized image space: x right, y down, 0...1.
enum Joint: String, CaseIterable, Codable, Sendable {
    case nose, neck
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

struct PoseFrame: Sendable {
    var timestamp: TimeInterval
    var joints: [Joint: CGPoint]

    subscript(_ joint: Joint) -> CGPoint? { joints[joint] }
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
