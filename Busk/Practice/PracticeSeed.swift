import Foundation
import SwiftData

/// Sample practice history for UI tests and screenshots (`-ui-testing -seed-practice N`): a beginner who shoots most
/// days and gets steadily better, so the tracker has streaks, gaps, trends and makes to show.
enum PracticeSeed {
    static func insert(days: Int, into context: ModelContext, now: Date = Date(), calendar: Calendar = .current) {
        var rng = SeededGenerator(seed: 7)
        let today = calendar.startOfDay(for: now)
        let evaluator = FormEvaluator()
        for back in stride(from: days - 1, through: 0, by: -1) {
            // A rest day every so often, but never today or yesterday, so the streak is live.
            if back > 1 && back % 5 == 3 { continue }
            guard let day = calendar.date(byAdding: .day, value: -back, to: today),
                  let start = calendar.date(byAdding: .hour, value: 17, to: day) else { continue }
            let progress = days > 1 ? 1 - Double(back) / Double(days - 1) : 1
            let count = back == 0 ? 24 : Int.random(in: 30...65, using: &rng)
            var shots: [ShotResult] = []
            for i in 0..<count {
                let sloppy = Double.random(in: 0...1, using: &rng) > progress * 0.8
                let metrics = ShotMetrics(view: .front,
                                          setPointHeight: sloppy ? Double.random(in: -0.04...0.08, using: &rng) : 0.14,
                                          elbowFlare: sloppy ? Double.random(in: 0.02...0.11, using: &rng) : 0.02,
                                          armAngle: nil,
                                          followThrough: sloppy ? Double.random(in: 0.1...0.8, using: &rng) : 0.8,
                                          legDrive: 0.04, releaseTiming: 0, hitch: 0, drift: 0.02, guideHandPush: 0.01)
                var shot = evaluator.evaluate(metrics)
                shot.date = start.addingTimeInterval(Double(i) * 20)
                shot.made = Double.random(in: 0...1, using: &rng) < 0.28 + 0.22 * progress
                shots.append(shot)
            }
            context.insert(SessionRecord(date: start, duration: Double(count) * 20, view: .front, handedness: .right,
                                         isDemo: false, shots: shots))
        }
        try? context.save()
    }
}

/// Deterministic so seeded screenshots look the same run to run.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
