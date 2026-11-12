import Foundation

/// One finished session as the practice tracker sees it.
struct PracticeEntry: Sendable {
    var date: Date
    var shots: [ShotResult]
    /// Shots that went in, when the player logged them.
    var makes: Int?

    var scores: [Int] { shots.map(\.score) }
}

/// Totals for one calendar day.
struct PracticeDay: Identifiable, Equatable, Sendable {
    var day: Date
    var sessions = 0
    var shots = 0
    var makes = 0
    /// Shots from sessions where makes were logged, the base for the make rate.
    var trackedShots = 0
    var scoreTotal = 0

    var id: Date { day }
    var averageScore: Int? { shots > 0 ? Int((Double(scoreTotal) / Double(shots)).rounded()) : nil }
    var makeRate: Double? { trackedShots > 0 ? Double(makes) / Double(trackedShots) : nil }
}

/// Then-versus-now numbers for one stretch of shots.
struct PracticeStretch: Equatable, Sendable {
    var shots: Int
    var averageScore: Int
    var makeRate: Double?
    var goodRate: [FormArea: Double]
}

/// Daily totals, streaks, bests and improvement across every saved session.
struct PracticeLog: Sendable {
    let entries: [PracticeEntry]
    let calendar: Calendar
    let now: Date
    let days: [Date: PracticeDay]

    init(entries: [PracticeEntry], now: Date = Date(), calendar: Calendar = .current) {
        self.entries = entries.sorted { $0.date < $1.date }
        self.calendar = calendar
        self.now = now
        var days: [Date: PracticeDay] = [:]
        for e in entries {
            let key = calendar.startOfDay(for: e.date)
            var d = days[key] ?? PracticeDay(day: key)
            d.sessions += 1
            d.shots += e.shots.count
            d.scoreTotal += e.scores.reduce(0, +)
            if let makes = e.makes {
                d.makes += makes
                d.trackedShots += e.shots.count
            }
            days[key] = d
        }
        self.days = days
    }

    var today: PracticeDay { day(now) }

    func day(_ date: Date) -> PracticeDay {
        let key = calendar.startOfDay(for: date)
        return days[key] ?? PracticeDay(day: key)
    }

    /// The last `count` days ending today, oldest first, including days without practice.
    func lastDays(_ count: Int) -> [PracticeDay] {
        let start = calendar.startOfDay(for: now)
        return (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: start) }.map(day)
    }

    /// Days in a row with practice, counting back from today, or from yesterday when today has none yet.
    var currentStreak: Int {
        var date = calendar.startOfDay(for: now)
        if days[date] == nil, let yesterday = calendar.date(byAdding: .day, value: -1, to: date) { date = yesterday }
        var streak = 0
        while days[date] != nil {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: date) else { break }
            date = previous
        }
        return streak
    }

    var longestStreak: Int {
        var best = 0, run = 0
        var previous: Date?
        for key in days.keys.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == key { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = key
        }
        return best
    }

    var totalShots: Int { entries.reduce(0) { $0 + $1.shots.count } }
    var totalMakes: Int { entries.reduce(0) { $0 + ($1.makes ?? 0) } }
    var practiceDays: Int { days.count }

    /// Days in the last `count` (ending today) that reached the shot goal.
    func goalDays(goal: Int, in count: Int) -> Int { lastDays(count).filter { $0.shots >= goal }.count }

    /// The first and latest `size` shots, so a player sees how far their form and shooting have come.
    /// Nil until there are enough shots for the two stretches not to overlap.
    func improvement(size: Int = 30) -> (then: PracticeStretch, now: PracticeStretch)? {
        let all = entries.flatMap { e in e.shots.map { ($0, e) } }
        guard all.count >= 2 * min(size, 10), entries.count >= 2 else { return nil }
        let n = min(size, all.count / 2)
        return (stretch(Array(all.prefix(n))), stretch(Array(all.suffix(n))))
    }

    private func stretch(_ shots: [(ShotResult, PracticeEntry)]) -> PracticeStretch {
        let average = Int((Double(shots.map(\.0.score).reduce(0, +)) / Double(max(1, shots.count))).rounded())
        var goodRate: [FormArea: Double] = [:]
        for area in FormArea.allCases {
            let results = shots.flatMap(\.0.areas).filter { $0.area == area }
            guard !results.isEmpty else { continue }
            goodRate[area] = Double(results.filter { $0.grade == .good }.count) / Double(results.count)
        }
        // Makes are logged per session, so a stretch's make rate comes from the sessions it draws on.
        var seen = Set<Date>(), makes = 0, tracked = 0
        for (_, e) in shots where seen.insert(e.date).inserted {
            if let m = e.makes { makes += m; tracked += e.shots.count }
        }
        return PracticeStretch(shots: shots.count, averageScore: average,
                               makeRate: tracked > 0 ? Double(makes) / Double(tracked) : nil, goodRate: goodRate)
    }

    /// The last 7 days against the 7 before them.
    var thisWeek: PracticeDay { week(endingDaysAgo: 0) }
    var lastWeek: PracticeDay { week(endingDaysAgo: 7) }

    private func week(endingDaysAgo offset: Int) -> PracticeDay {
        let end = calendar.startOfDay(for: now)
        var total = PracticeDay(day: calendar.date(byAdding: .day, value: -offset - 6, to: end) ?? end)
        for i in offset..<(offset + 7) {
            guard let date = calendar.date(byAdding: .day, value: -i, to: end), let d = days[date] else { continue }
            total.sessions += d.sessions
            total.shots += d.shots
            total.makes += d.makes
            total.trackedShots += d.trackedShots
            total.scoreTotal += d.scoreTotal
        }
        return total
    }

    // Personal bests.
    var bestSessionScore: Int? {
        entries.filter { !$0.shots.isEmpty }.map { SessionSummary(shots: $0.shots).averageScore }.max()
    }
    var mostShotsInADay: Int? { days.values.map(\.shots).max() }
    /// Best make rate on a day with at least 10 logged shots.
    var bestMakeDay: PracticeDay? {
        days.values.filter { $0.trackedShots >= 10 }.max { ($0.makeRate ?? 0) < ($1.makeRate ?? 0) }
    }

    /// The area that needed work most often across the latest `count` shots.
    func focus(lastShots count: Int = 50) -> FormArea? {
        SessionSummary(shots: Array(entries.flatMap(\.shots).suffix(count))).topFocus
    }
}

extension PracticeLog {
    /// Demo sessions are the built-in shooter, not the player, so they never count toward the tracker.
    init(records: [SessionRecord], now: Date = Date(), calendar: Calendar = .current) {
        self.init(entries: records.filter { !$0.isDemo }.map { PracticeEntry(date: $0.date, shots: $0.shots, makes: $0.makes) }, now: now, calendar: calendar)
    }
}

enum PracticeGoal {
    static let defaultShots = 50
    static let range = 10...500
}
