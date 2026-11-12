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

    init(date: Date, duration: TimeInterval, view: CameraView, handedness: Handedness, isDemo: Bool, shots: [ShotResult]) {
        self.date = date
        self.duration = duration
        self.viewRaw = view.rawValue
        self.handednessRaw = handedness.rawValue
        self.isDemo = isDemo
        self.shotsData = (try? JSONEncoder().encode(shots)) ?? Data()
    }

    var shots: [ShotResult] { (try? JSONDecoder().decode([ShotResult].self, from: shotsData)) ?? [] }
    var view: CameraView { CameraView(rawValue: viewRaw) ?? .side }
    var summary: SessionSummary { SessionSummary(shots: shots) }
}

/// Aggregates a set of shots for the summary screen.
struct SessionSummary {
    let shots: [ShotResult]

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
