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

/// The form areas Busk coaches. Each matches one flaw in the shooting-feedback benchmark taxonomy.
/// Busk coaches clearly bad areas before marginal ones, then in `coachingPriority` order (the taxonomy's
/// `coaching_priority`); within a rank the area furthest off goes first, then declaration order.
enum FormArea: String, Codable, CaseIterable, Identifiable, Sendable {
    case setPoint, balance, releaseTiming, rhythm, elbow, guideHand, arc, legs, followThrough
    var id: String { rawValue }
    var priority: Int { FormArea.allCases.firstIndex(of: self) ?? 0 }
    var coachingPriority: Int {
        switch self {
        case .setPoint, .rhythm: return 1
        case .legs, .balance: return 2
        case .releaseTiming, .elbow, .guideHand: return 3
        case .arc, .followThrough: return 4
        }
    }
    var title: String {
        switch self {
        case .setPoint: return "Set point"
        case .releaseTiming: return "Release timing"
        case .balance: return "Balance"
        case .rhythm: return "Rhythm"
        case .elbow: return "Elbow"
        case .guideHand: return "Guide hand"
        case .arc: return "Arc"
        case .legs: return "Legs"
        case .followThrough: return "Follow-through"
        }
    }
    var cue: String {
        switch self {
        case .setPoint: return "Bring the ball up above your forehead before you shoot, not from your chest"
        case .releaseTiming: return "Release at the top of your jump, not on the way down"
        case .balance: return "Jump straight up and land where you took off"
        case .rhythm: return "One smooth motion, don't stop the ball at your set point"
        case .elbow: return "Tuck your shooting elbow under the ball"
        case .guideHand: return "Guide hand on the side, let it come off clean"
        case .arc: return "More arc, shoot up and over the rim"
        case .legs: return "Bend your knees and drive up through your legs"
        case .followThrough: return "Snap your wrist and hold your follow-through"
        }
    }
    /// Flaw ID in benchmark/taxonomy.json.
    var flawID: String {
        switch self {
        case .setPoint: return "low_set_point"
        case .releaseTiming: return "releasing_on_the_way_down"
        case .balance: return "off_balance_drift"
        case .rhythm: return "hitch_at_set_point"
        case .elbow: return "elbow_flare"
        case .guideHand: return "guide_hand_interference"
        case .arc: return "flat_arc"
        case .legs: return "no_leg_drive"
        case .followThrough: return "no_follow_through"
        }
    }
    var symbol: String {
        switch self {
        case .setPoint: return "hand.raised"
        case .releaseTiming: return "arrow.up.to.line"
        case .balance: return "figure.stand"
        case .rhythm: return "metronome"
        case .elbow: return "arrow.down.right.and.arrow.up.left"
        case .guideHand: return "hand.wave"
        case .arc: return "point.topleft.down.to.point.bottomright.curvepath"
        case .legs: return "figure.basketball"
        case .followThrough: return "hand.point.down"
        }
    }
}

struct AreaResult: Codable, Equatable, Identifiable, Sendable {
    var area: FormArea
    var grade: Grade
    var value: Double
    var detail: String
    /// How far past the needs-work line the measurement is (0 when it isn't). Picks which cue comes first.
    var severity: Double = 0
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
    /// Every area that needs work, most important first.
    var fixes: [FormArea] = []
}

struct FormEvaluator {
    /// One check: `ok` and `bad` are the lines where a measurement turns from good to OK and from OK to needs work.
    /// Each measurement has its own scale, so the flaw to fix first is the one furthest past `bad` as a share of the way
    /// to `worst`, a clearly severe value (set from how flaws rank on random held-out shooters).
    /// `clear` is where Busk's measurement crosses the taxonomy's `bad` line: past it the flaw is clearly bad,
    /// before it marginal (defaults to `bad`).
    struct Limit {
        var ok: Double, bad: Double, worst: Double
        var clear: Double? = nil
        /// Larger values are worse when `bad > ok`.
        func grade(_ v: Double) -> Grade {
            bad > ok ? (v > bad ? .needsWork : v > ok ? .ok : .good) : (v < bad ? .needsWork : v < ok ? .ok : .good)
        }
        func severity(_ v: Double) -> Double { max(0, (v - bad) / (worst - bad)) }
        func isClear(_ v: Double) -> Bool { bad > ok ? v >= (clear ?? bad) : v <= (clear ?? bad) }
    }

    struct Thresholds {
        var setPoint = Limit(ok: 0.06, bad: 0.0, worst: -0.06, clear: -0.045)
        var releaseTiming = Limit(ok: 0.20, bad: 0.30, worst: 0.55, clear: 0.38)
        var drift = Limit(ok: 0.11, bad: 0.16, worst: 0.24)
        var hitch = Limit(ok: 0.22, bad: 0.30, worst: 0.54, clear: 0.44)
        var elbow = Limit(ok: 0.055, bad: 0.075, worst: 0.085, clear: 0.076)
        var guideHand = Limit(ok: 0.025, bad: 0.035, worst: 0.042)
        var armAngle = Limit(ok: 64, bad: 59, worst: 55, clear: 56)
        var legDrive = Limit(ok: 0.028, bad: 0.016, worst: 0.004, clear: 0.0075)
        var followThrough = Limit(ok: 0.40, bad: 0.25, worst: 0.19, clear: 0.21)
    }

    var thresholds = Thresholds()

    func evaluate(_ m: ShotMetrics) -> ShotResult {
        let t = thresholds
        var areas: [AreaResult] = []
        var marginal: Set<FormArea> = []
        func add(_ area: FormArea, _ value: Double?, _ limit: Limit, _ detail: (Double) -> String) {
            guard let value else { return }
            let grade = limit.grade(value)
            if grade == .needsWork && !limit.isClear(value) { marginal.insert(area) }
            areas.append(AreaResult(area: area, grade: grade, value: value, detail: detail(value),
                                    severity: grade == .needsWork ? 1 + limit.severity(value) : 0))
        }
        add(.setPoint, m.setPointHeight, t.setPoint) { $0 < 0 ? "Ball set below your shoulders" : "Ball set above your head" }
        add(.releaseTiming, m.releaseTiming, t.releaseTiming) { $0 > 0.3 ? "Let go after the peak of your jump" : "Released near the top of your jump" }
        add(.balance, m.drift, t.drift) { String(format: "Moved %.0f%% of your height in the air", $0 * 100) }
        add(.rhythm, m.hitch, t.hitch) { String(format: "Ball paused %.2f s at the set point", $0) }
        add(.elbow, m.elbowFlare, t.elbow) { String(format: "Elbow %.0f%% of your height outside the ball", $0 * 100) }
        add(.guideHand, m.guideHandPush, t.guideHand) { $0 > t.guideHand.bad ? "Guide hand pushed the ball" : "Guide hand came off clean" }
        add(.arc, m.armAngle, t.armAngle) { "Launch about \(Int(($0 - 20).rounded()))°" }
        add(.legs, m.legDrive, t.legDrive) { $0 < 0.013 ? "Barely any knee bend" : "Good dip into your legs" }
        add(.followThrough, m.followThrough, t.followThrough) { String(format: "Held %.1f s", $0) }

        let penalty = areas.map { (r: AreaResult) -> Int in r.grade == .needsWork ? 20 : r.grade == .ok ? 7 : 0 }.reduce(0, +)
        let needsWork: [AreaResult] = areas.filter { $0.grade == .needsWork }
        let fixes: [FormArea] = needsWork.sorted { (a: AreaResult, b: AreaResult) -> Bool in
            if marginal.contains(a.area) != marginal.contains(b.area) { return !marginal.contains(a.area) }
            if a.area.coachingPriority != b.area.coachingPriority {
                return a.area.coachingPriority < b.area.coachingPriority
            }
            return a.severity != b.severity ? a.severity > b.severity : a.area.priority < b.area.priority
        }.map(\.area)
        let focus = fixes.first
        return ShotResult(metrics: m, areas: areas, score: max(0, 100 - penalty),
                          cue: focus?.cue ?? "Great shot, same again", focus: focus, fixes: fixes)
    }
}
