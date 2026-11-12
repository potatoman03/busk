import Foundation

/// One finished session as the coaching plan sees it.
struct PracticeSession: Sendable {
    var date: Date
    var focus: FormArea?
    var shots: [ShotResult]
}

/// How far along a player is with one form area, from their recent shots.
struct AreaProgress: Identifiable, Sendable {
    enum Stage: Int, Comparable, Sendable {
        case unmeasured, learning, building, solid, lockedIn
        static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
        var label: String {
            switch self {
            case .unmeasured: return "Not seen yet"
            case .learning: return "Learning"
            case .building: return "Building"
            case .solid: return "Solid"
            case .lockedIn: return "Locked in"
            }
        }
    }

    let area: FormArea
    /// Grades of the most recent measured shots, oldest first (at most `CoachPlan.window`).
    let recent: [Grade]
    /// Good rate over the window before `recent`, to show a trend. Nil with too few older shots.
    let previousGoodRate: Double?
    var id: FormArea { area }

    var measured: Int { recent.count }
    var good: Int { recent.filter { $0 == .good }.count }
    var goodRate: Double { measured == 0 ? 0 : Double(good) / Double(measured) }
    var needsWorkRate: Double { measured == 0 ? 0 : Double(recent.filter { $0 == .needsWork }.count) / Double(measured) }
    /// Change in good rate since the previous window, in percentage points.
    var trend: Int? { previousGoodRate.map { Int(((goodRate - $0) * 100).rounded()) } }

    var stage: Stage {
        if measured < CoachPlan.minimumToJudge { return .unmeasured }
        if measured >= CoachPlan.lockedInShots && goodRate >= CoachPlan.lockedInRate { return .lockedIn }
        if measured >= CoachPlan.graduateShots && goodRate >= CoachPlan.graduateRate { return .solid }
        return goodRate >= 0.4 ? .building : .learning
    }
}

/// The player's coaching plan: what they're working on, how each part of their shot is going, and today's workout.
struct CoachPlan: Sendable {
    /// Shots per area the stages look at.
    static let window = 30
    static let minimumToJudge = 5
    /// An area graduates (Solid) at 70% good over at least 15 measured shots.
    static let graduateShots = 15
    static let graduateRate = 0.7
    static let lockedInShots = 30
    static let lockedInRate = 0.85
    /// Shots needed before Busk picks a focus.
    static let baselineShots = 10
    static let focusSetShots = 20

    let areas: [AreaProgress]
    let totalShots: Int
    /// What to work on now. Nil until there are enough shots for a baseline.
    let focus: FormArea?
    /// Areas that reached Solid after being a focus.
    let graduated: [FormArea]

    /// Curriculum order: build from the ground up, so a focus on the legs comes before one on the follow-through.
    static let order: [FormArea] = Lesson.all.compactMap(\.area)

    init(sessions: [PracticeSession]) {
        let sorted = sessions.sorted { $0.date < $1.date }
        let shots = sorted.flatMap(\.shots)
        totalShots = shots.count
        areas = Self.order.map { area in
            let grades = shots.compactMap { $0.areas.first { $0.area == area }?.grade }
            let recent = Array(grades.suffix(Self.window))
            let older = grades.dropLast(recent.count).suffix(Self.window)
            let previous = older.count >= Self.minimumToJudge
                ? Double(older.filter { $0 == .good }.count) / Double(older.count) : nil
            return AreaProgress(area: area, recent: recent, previousGoodRate: previous)
        }

        // A focus sticks until it graduates, so the player isn't bounced between fixes from day to day.
        let byArea = Dictionary(uniqueKeysWithValues: areas.map { ($0.area, $0) })
        let practised = Set(sorted.compactMap(\.focus))
        graduated = Self.order.filter { practised.contains($0) && (byArea[$0]?.stage ?? .unmeasured) >= .solid }
        if let current = sorted.last(where: { $0.focus != nil })?.focus, (byArea[current]?.stage ?? .unmeasured) < .solid {
            focus = current
        } else if totalShots >= Self.baselineShots {
            focus = Self.pickFocus(areas)
        } else {
            focus = nil
        }
    }

    /// The area that needs work most often; ties go to the one earlier in the curriculum.
    static func pickFocus(_ areas: [AreaProgress]) -> FormArea? {
        let candidates = areas.filter { $0.measured >= minimumToJudge && $0.stage < .solid && $0.needsWorkRate > 0 }
        return candidates.max { a, b in
            abs(a.needsWorkRate - b.needsWorkRate) > 0.001
                ? a.needsWorkRate < b.needsWorkRate
                : order.firstIndex(of: a.area)! > order.firstIndex(of: b.area)!
        }?.area ?? areas.filter { $0.measured >= minimumToJudge && $0.stage < .solid }
            .min { $0.goodRate < $1.goodRate }?.area
    }

    func progress(for area: FormArea) -> AreaProgress? { areas.first { $0.area == area } }

    /// Goal for the next focus set: a bit better than now, between 50% and 90% good.
    func goalRate(for area: FormArea) -> Double {
        let current = progress(for: area).flatMap { $0.measured >= Self.minimumToJudge ? $0.goodRate : nil } ?? 0.4
        return min(0.9, max(0.5, ((current + 0.1) * 20).rounded() / 20))
    }

    /// Why this focus, in a sentence.
    var focusReason: String? {
        guard let focus, let p = progress(for: focus) else { return nil }
        if p.measured < Self.minimumToJudge { return "Busk hasn't measured your \(focus.title.lowercased()) much yet." }
        let off = p.measured - p.good
        return "\(off) of your last \(p.measured) shots weren't right on your \(focus.title.lowercased()). Get it to \(Int(Self.graduateRate * 100))% good to move on."
    }

    /// Today's workout, in order.
    func workout(hasBall: Bool) -> [WorkoutStep] {
        guard let focus else {
            return [
                WorkoutStep(id: "lesson-overview", kind: .lesson(Lesson.byID("overview")!), title: "Learn the four beats",
                            detail: "Two minutes on how a jump shot works."),
                WorkoutStep(id: "baseline", kind: .trackedSet(focus: nil, shots: 15),
                            title: hasBall ? "Baseline: 15 shots" : "Baseline: 15 shadow shots",
                            detail: hasBall ? "Shoot from 2-3 m. Busk finds what to work on first."
                                : "Full shooting motion, no ball. Busk finds what to work on first."),
            ]
        }
        let lesson = Lesson.forArea(focus)!
        let drills = lesson.drills.filter { hasBall || !$0.needsBall }
        let warmUp = Drill.byID(hasBall ? "formShooting" : "shadow")!
        var steps = [
            WorkoutStep(id: "warmup", kind: .drill(warmUp), title: "Warm up: \(warmUp.title.lowercased())",
                        detail: hasBall ? "5 makes from 1 m, then 2 m." : "10 easy reps, full motion."),
            WorkoutStep(id: "lesson-\(lesson.id)", kind: .lesson(lesson), title: "Lesson: \(lesson.title)", detail: lesson.summary),
        ]
        if let drill = drills.first(where: { $0.id != warmUp.id }) {
            steps.append(WorkoutStep(id: "drill-\(drill.id)", kind: .drill(drill), title: drill.title, detail: drill.dose))
        }
        let goal = Int((goalRate(for: focus) * Double(Self.focusSetShots)).rounded())
        steps.append(WorkoutStep(id: "focus-\(focus.rawValue)", kind: .trackedSet(focus: focus, shots: Self.focusSetShots),
                                 title: "Focus set: \(Self.focusSetShots) \(hasBall ? "shots" : "shadow shots")",
                                 detail: "Busk only coaches your \(focus.title.lowercased()). Goal: \(goal) of \(Self.focusSetShots) good."))
        return steps
    }
}

struct WorkoutStep: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case lesson(Lesson)
        case drill(Drill)
        /// A session Busk tracks; with a focus, the coach only cues that area.
        case trackedSet(focus: FormArea?, shots: Int)
    }
    let id: String
    let kind: Kind
    let title: String
    let detail: String

    var symbol: String {
        switch kind {
        case .lesson: return "book"
        case .drill(let d): return d.needsBall ? "basketball" : "figure.run"
        case .trackedSet: return "camera.viewfinder"
        }
    }
}

/// Which of today's workout steps the player has ticked off. Stored per day in UserDefaults.
enum WorkoutChecklist {
    static func key(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "workoutDone-\(c.year!)-\(c.month!)-\(c.day!)"
    }

    static func done(on date: Date = Date(), defaults: UserDefaults = .standard) -> Set<String> {
        Set(defaults.stringArray(forKey: key(for: date)) ?? [])
    }

    static func set(_ id: String, done: Bool, on date: Date = Date(), defaults: UserDefaults = .standard) {
        var ids = self.done(on: date, defaults: defaults)
        if done { ids.insert(id) } else { ids.remove(id) }
        defaults.set(ids.sorted(), forKey: key(for: date))
    }

    /// Tracked sets count as done once a session with that focus was saved today; other steps once checked off.
    static func isDone(_ step: WorkoutStep, checked: Set<String>, sessions: [PracticeSession], now: Date = Date()) -> Bool {
        if case .trackedSet(let focus, _) = step.kind {
            let today = sessions.filter { Calendar.current.isDate($0.date, inSameDayAs: now) }
            if today.contains(where: { $0.focus == focus && !$0.shots.isEmpty }) { return true }
        }
        return checked.contains(step.id)
    }
}
