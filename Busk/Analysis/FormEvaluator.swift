import Foundation

enum Grade: Int, Codable, Comparable, Sendable {
    case good = 0, ok = 1, needsWork = 2
    static func < (a: Grade, b: Grade) -> Bool { a.rawValue < b.rawValue }
    var label: String {
        switch self {
        case .good: return "Good"
        case .ok: return "OK"
        case .needsWork: return "Needs work"
        }
    }
}

/// The four coaching areas plus legs, in the order cues are prioritized.
enum FormArea: String, Codable, CaseIterable, Identifiable, Sendable {
    case elbow, arc, armExtension, releaseHeight, followThrough, legs
    var id: String { rawValue }
    var title: String {
        switch self {
        case .elbow: return "Elbow"
        case .arc: return "Arc"
        case .armExtension: return "Release extension"
        case .releaseHeight: return "Release point"
        case .followThrough: return "Follow-through"
        case .legs: return "Legs"
        }
    }
    var cue: String {
        switch self {
        case .elbow: return "Tuck your elbow under the ball"
        case .arc: return "More arc, shoot up not out"
        case .armExtension: return "Extend all the way up"
        case .releaseHeight: return "Release higher, above your forehead"
        case .followThrough: return "Hold your follow-through"
        case .legs: return "Bend your knees more"
        }
    }
    var symbol: String {
        switch self {
        case .elbow: return "arrow.down.right.and.arrow.up.left"
        case .arc: return "point.topleft.down.to.point.bottomright.curvepath"
        case .armExtension: return "arrow.up.to.line"
        case .releaseHeight: return "hand.raised"
        case .followThrough: return "hand.point.down"
        case .legs: return "figure.basketball"
        }
    }
}

struct AreaResult: Codable, Equatable, Identifiable, Sendable {
    var area: FormArea
    var grade: Grade
    var value: Double
    var detail: String
    var id: FormArea { area }
}

struct ShotResult: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    var metrics: ShotMetrics
    var areas: [AreaResult]
    var score: Int
    /// What the coach says out loud after this shot.
    var cue: String
    var focus: FormArea?
}

struct FormEvaluator {
    struct Thresholds {
        var elbowOffsetGood = 0.30, elbowOffsetOK = 0.50
        var extensionGood = 160.0, extensionOK = 150.0
        var heightGood = 0.45, heightOK = 0.25
        var arcGood = 52.0...82.0, arcOK = 45.0...88.0
        var followGood = 0.40, followOK = 0.20
        var kneeGood = 150.0, kneeOK = 162.0
    }

    var thresholds = Thresholds()

    func evaluate(_ m: ShotMetrics) -> ShotResult {
        let t = thresholds
        var areas: [AreaResult] = []

        areas.append(AreaResult(area: .elbow,
                                grade: m.elbowOffset <= t.elbowOffsetGood ? .good : m.elbowOffset <= t.elbowOffsetOK ? .ok : .needsWork,
                                value: m.elbowOffset,
                                detail: "Elbow \(Int((m.elbowOffset * 100).rounded()))% of a forearm off the ball line"))
        if let arc = m.releaseAngle {
            areas.append(AreaResult(area: .arc,
                                    grade: t.arcGood.contains(arc) ? .good : t.arcOK.contains(arc) ? .ok : .needsWork,
                                    value: arc,
                                    detail: "Released at \(Int(arc.rounded()))° (aim for 55-75°)"))
        }
        areas.append(AreaResult(area: .armExtension,
                                grade: m.releaseElbowAngle >= t.extensionGood ? .good : m.releaseElbowAngle >= t.extensionOK ? .ok : .needsWork,
                                value: m.releaseElbowAngle,
                                detail: "Elbow opened to \(Int(m.releaseElbowAngle.rounded()))°"))
        areas.append(AreaResult(area: .releaseHeight,
                                grade: m.releaseHeight >= t.heightGood ? .good : m.releaseHeight >= t.heightOK ? .ok : .needsWork,
                                value: m.releaseHeight,
                                detail: m.releaseHeight >= t.heightGood ? "High release" : "Release is low"))
        areas.append(AreaResult(area: .followThrough,
                                grade: m.followThrough >= t.followGood ? .good : m.followThrough >= t.followOK ? .ok : .needsWork,
                                value: m.followThrough,
                                detail: String(format: "Held %.1fs", m.followThrough)))
        if let knee = m.kneeAngle {
            areas.append(AreaResult(area: .legs,
                                    grade: knee <= t.kneeGood ? .good : knee <= t.kneeOK ? .ok : .needsWork,
                                    value: knee,
                                    detail: "Knees bent to \(Int(knee.rounded()))°"))
        }

        let penalty = areas.reduce(0) { $0 + ($1.grade == .needsWork ? 20 : $1.grade == .ok ? 7 : 0) }
        let score = max(0, 100 - penalty)
        let focus = areas.first { $0.grade == .needsWork }?.area ?? areas.first { $0.grade == .ok }?.area
        let cue: String
        if let f = focus, areas.contains(where: { $0.area == f && $0.grade == .needsWork }) {
            cue = f.cue
        } else if score >= 90 {
            cue = "Great shot, same again"
        } else if let f = focus {
            cue = "Nice. " + f.cue
        } else {
            cue = "Great shot, same again"
        }
        return ShotResult(metrics: m, areas: areas, score: score, cue: cue, focus: focus)
    }
}
