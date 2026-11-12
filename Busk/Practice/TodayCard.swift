import SwiftUI

/// Home's daily tracker: today's shots against the goal, makes, the streak and the last seven days.
struct TodayCard: View {
    let log: PracticeLog
    let goal: Int

    var body: some View {
        let today = log.today
        Card {
            HStack(spacing: 16) {
                GoalRing(value: today.shots, goal: goal)
                    .frame(width: 76, height: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today").font(.caption).foregroundStyle(.secondary)
                    Text("\(today.shots) of \(goal) shots")
                        .font(.title3.bold().monospacedDigit())
                        .accessibilityIdentifier("todayShots")
                    Text(makesLine(today)).font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("todayMakes")
                }
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    Image(systemName: "flame.fill").foregroundStyle(log.currentStreak > 0 ? Theme.orange : .secondary)
                    Text("\(log.currentStreak)").font(.title2.bold().monospacedDigit())
                        .accessibilityIdentifier("streakCount")
                    Text(log.currentStreak == 1 ? "day" : "days").font(.caption2).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(log.currentStreak) day streak")
            }
            WeekStrip(days: log.lastDays(7), goal: goal)
        }
    }

    private func makesLine(_ day: PracticeDay) -> String {
        if day.shots == 0 { return log.currentStreak > 0 ? "Shoot today to keep your streak" : "Start a streak today" }
        if day.shots >= goal { return "Goal hit" + (day.makeRate.map { " · \(Self.percent($0)) made" } ?? "") }
        guard let rate = day.makeRate else { return "\(goal - day.shots) to go" }
        return "\(day.makes) made · \(Self.percent(rate))"
    }

    static func percent(_ rate: Double) -> String { "\(points(rate))%" }
    static func points(_ rate: Double) -> Int { Int((rate * 100).rounded()) }
    /// Change in whole percentage points, matching the two percents shown.
    static func pointsChange(from a: Double, to b: Double) -> Int { points(b) - points(a) }
}

struct GoalRing: View {
    let value: Int
    let goal: Int
    var body: some View {
        let progress = min(1, Double(value) / Double(max(1, goal)))
        ZStack {
            Circle().stroke(.white.opacity(0.12), lineWidth: 9)
            Circle().trim(from: 0, to: progress)
                .stroke(value >= goal ? Color.green : Theme.orange, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if value >= goal {
                Image(systemName: "checkmark").font(.title2.bold()).foregroundStyle(.green)
            } else {
                Text("\(Int((progress * 100).rounded()))%").font(.subheadline.bold().monospacedDigit())
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(value) of \(goal) shots")
        .accessibilityIdentifier("goalRing")
    }
}

/// One dot per day: filled when the goal was hit, part-filled for some practice.
struct WeekStrip: View {
    let days: [PracticeDay]
    let goal: Int
    var body: some View {
        HStack(spacing: 0) {
            ForEach(days) { day in
                VStack(spacing: 4) {
                    Text(day.day, format: .dateTime.weekday(.narrow)).font(.caption2).foregroundStyle(.secondary)
                    Circle()
                        .fill(DayShade.color(shots: day.shots, goal: goal))
                        .overlay(Circle().stroke(Calendar.current.isDateInToday(day.day) ? Color.white : .clear, lineWidth: 1.5))
                        .frame(width: 22, height: 22)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("weekStrip")
    }
}

enum DayShade {
    static func color(shots: Int, goal: Int) -> Color {
        guard shots > 0 else { return .white.opacity(0.08) }
        if shots >= goal { return .green }
        return Theme.orange.opacity(0.3 + 0.6 * min(1, Double(shots) / Double(max(1, goal))))
    }
}
