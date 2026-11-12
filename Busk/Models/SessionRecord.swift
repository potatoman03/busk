import Foundation
import SwiftData

@Model
final class SessionRecord {
    var date: Date
    var duration: TimeInterval
    var viewRaw: String
    var handednessRaw: String
    var isDemo: Bool
    var shotsData: Data
    /// Shots that went in, when the player logged them (live Made/Missed taps, voice, or the summary).
    var makes: Int?

    init(date: Date, duration: TimeInterval, view: CameraView, handedness: Handedness, isDemo: Bool, shots: [ShotResult],
         makes: Int? = nil) {
        self.date = date
        self.duration = duration
        self.viewRaw = view.rawValue
        self.handednessRaw = handedness.rawValue
        self.isDemo = isDemo
        self.shotsData = (try? JSONEncoder().encode(shots)) ?? Data()
        self.makes = makes ?? SessionSummary(shots: shots).makes
    }

    var shots: [ShotResult] { (try? JSONDecoder().decode([ShotResult].self, from: shotsData)) ?? [] }
    var view: CameraView { CameraView(rawValue: viewRaw) ?? .side }
    var summary: SessionSummary { SessionSummary(shots: shots, makes: makes) }

    /// "12 min", or "<1 min" for a quick one.
    var durationText: String {
        duration < 60 ? "<1 min" : "\(Int((duration / 60).rounded())) min"
    }
}

/// Aggregates a set of shots for the summary screen.
struct SessionSummary {
    let shots: [ShotResult]
    private let loggedMakes: Int?

    init(shots: [ShotResult], makes: Int? = nil) {
        self.shots = shots
        loggedMakes = makes
    }

    /// Shots that went in: the logged total, else the shots marked made, else nil when nothing was logged.
    var makes: Int? {
        if let loggedMakes { return loggedMakes }
        return shots.contains { $0.made != nil } ? shots.filter { $0.made == true }.count : nil
    }
    var makeRate: Double? { makes.flatMap { count > 0 ? Double($0) / Double(count) : nil } }

    var count: Int { shots.count }
    var averageScore: Int {
        guard !shots.isEmpty else { return 0 }
        return Int((Double(shots.map(\.score).reduce(0, +)) / Double(shots.count)).rounded())
    }
    var bestScore: Int { shots.map(\.score).max() ?? 0 }

    /// Share of shots graded good, per area.
    var areaBreakdown: [(area: FormArea, goodRate: Double, worst: Grade)] {
        FormArea.allCases.compactMap { area in
            let results = shots.flatMap(\.areas).filter { $0.area == area }
            guard !results.isEmpty else { return nil }
            let good = Double(results.filter { $0.grade == .good }.count) / Double(results.count)
            return (area, good, results.map(\.grade).max() ?? .good)
        }
    }

    /// A short spoken answer to "how am I doing".
    var spokenStatus: String {
        guard count > 0 else { return "No shots yet. Shoot when you're ready." }
        var parts = ["\(count) \(count == 1 ? "shot" : "shots"), average form \(averageScore), best \(bestScore)."]
        if let makes { parts.append("\(makes) of \(count) went in.") }
        if count >= 4 {
            let recent = shots.suffix(3).map(\.score)
            let recentAverage = Int((Double(recent.reduce(0, +)) / Double(recent.count)).rounded())
            if recentAverage >= averageScore + 5 {
                parts.append("Last three are better, averaging \(recentAverage).")
            } else if recentAverage <= averageScore - 5 {
                parts.append("Last three dipped to \(recentAverage).")
            }
        }
        if let focus = topFocus {
            parts.append("Main thing: \(focus.title.lowercased()). \(focus.cue).")
        } else {
            parts.append("Form looks clean. Keep it going.")
        }
        return parts.joined(separator: " ")
    }

    /// The area that most often needed work.
    var topFocus: FormArea? {
        let counts = Dictionary(grouping: shots.compactMap(\.focus), by: { $0 }).mapValues(\.count)
        return counts.max { a, b in a.value == b.value ? a.key.priority > b.key.priority : a.value < b.value }?.key
    }
}
