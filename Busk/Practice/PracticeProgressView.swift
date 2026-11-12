import Charts
import SwiftData
import SwiftUI

/// The practice tracker: streaks, the daily calendar, form and make-rate trends, then-versus-now and personal bests.
struct PracticeProgressView: View {
    @Query(sort: \SessionRecord.date) private var records: [SessionRecord]
    @AppStorage(SettingsKey.dailyShotGoal) private var goal = PracticeGoal.defaultShots

    var body: some View {
        let log = PracticeLog(records: records)
        Group {
            if log.practiceDays == 0 {
                ContentUnavailableView("No practice yet", systemImage: "chart.line.uptrend.xyaxis",
                                       description: Text("Finish a shooting session and your streak, shots and makes start here. Demo sessions don't count."))
                    .accessibilityIdentifier("progressEmpty")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        headline(log)
                        TodayCard(log: log, goal: goal)
                        calendar(log)
                        shotsChart(log)
                        formChart(log)
                        makesChart(log)
                        improvement(log)
                        week(log)
                        bests(log)
                    }
                    .padding(20)
                }
                .accessibilityIdentifier("progressScroll")
            }
        }
        .background(Theme.court.ignoresSafeArea())
        .navigationTitle("Progress")
    }

    private func headline(_ log: PracticeLog) -> some View {
        HStack(spacing: 12) {
            stat("\(log.currentStreak)", "day streak", symbol: "flame.fill", id: "progressStreak")
            stat("\(log.totalShots)", "shots", symbol: "basketball", id: "progressTotalShots")
            stat(log.totalMakes > 0 ? "\(log.totalMakes)" : "–", "makes", symbol: "checkmark.circle", id: "progressTotalMakes")
        }
    }

    private func calendar(_ log: PracticeLog) -> some View {
        Card {
            HStack {
                Text("Last 5 weeks").font(.headline)
                Spacer()
                Text("\(log.goalDays(goal: goal, in: 35)) goal days").font(.caption).foregroundStyle(.secondary)
            }
            let days = log.lastDays(35)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(days) { day in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(DayShade.color(shots: day.shots, goal: goal))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Text(day.day, format: .dateTime.day()).font(.caption2.monospacedDigit())
                                .foregroundStyle(day.shots > 0 ? .white : .secondary)
                        }
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Calendar.current.isDateInToday(day.day) ? .white : .clear))
                }
            }
            HStack(spacing: 12) {
                legend(DayShade.color(shots: 0, goal: goal), "Rest")
                legend(DayShade.color(shots: goal / 2, goal: goal), "Practiced")
                legend(.green, "Goal \(goal)+")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("practiceCalendar")
    }

    private func shotsChart(_ log: PracticeLog) -> some View {
        Card {
            Text("Shots per day").font(.headline)
            Chart {
                ForEach(log.lastDays(14)) { day in
                    BarMark(x: .value("Day", day.day, unit: .day), y: .value("Shots", day.shots))
                        .foregroundStyle(day.shots >= goal ? Color.green : Theme.orange)
                }
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.white.opacity(0.6))
                    .annotation(position: .top, alignment: .leading) { Text("Goal").font(.caption2).foregroundStyle(.secondary) }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in AxisValueLabel(format: .dateTime.day()) } }
            .frame(height: 150)
        }
        .accessibilityIdentifier("shotsChart")
    }

    private func formChart(_ log: PracticeLog) -> some View {
        let days = log.lastDays(30).filter { $0.averageScore != nil }
        return Card {
            HStack {
                Text("Form score").font(.headline)
                Spacer()
                if let first = days.first?.averageScore, let last = days.last?.averageScore, days.count > 1 {
                    Change(delta: last - first, unit: "")
                }
            }
            Chart(days) { day in
                LineMark(x: .value("Day", day.day, unit: .day), y: .value("Form", day.averageScore ?? 0))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Theme.orange)
                PointMark(x: .value("Day", day.day, unit: .day), y: .value("Form", day.averageScore ?? 0))
                    .foregroundStyle(Theme.color(forScore: day.averageScore ?? 0))
            }
            .chartYScale(domain: 0...100)
            .frame(height: 150)
            Text("Daily average over the last 30 days").font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("formChart")
    }

    @ViewBuilder private func makesChart(_ log: PracticeLog) -> some View {
        let days = log.lastDays(30).filter { $0.makeRate != nil }
        if !days.isEmpty {
            Card {
                HStack {
                    Text("Make rate").font(.headline)
                    Spacer()
                    if let first = days.first?.makeRate, let last = days.last?.makeRate, days.count > 1 {
                        Change(delta: Int(((last - first) * 100).rounded()), unit: " pts")
                    }
                }
                Chart(days) { day in
                    AreaMark(x: .value("Day", day.day, unit: .day), y: .value("Made", (day.makeRate ?? 0) * 100))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.linearGradient(colors: [.green.opacity(0.5), .green.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Day", day.day, unit: .day), y: .value("Made", (day.makeRate ?? 0) * 100))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(.green)
                }
                .chartYScale(domain: 0...100)
                .chartYAxis { AxisMarks { v in AxisGridLine(); AxisValueLabel { Text("\(v.as(Int.self) ?? 0)%") } } }
                .frame(height: 130)
            }
            .accessibilityIdentifier("makesChart")
        }
    }

    @ViewBuilder private func improvement(_ log: PracticeLog) -> some View {
        if let (then, now) = log.improvement() {
            Card {
                Text("How far you've come").font(.headline)
                Text("Your first \(then.shots) shots against your latest \(now.shots)").font(.caption).foregroundStyle(.secondary)
                compareRow("Form score", then: "\(then.averageScore)", now: "\(now.averageScore)", delta: now.averageScore - then.averageScore)
                if let a = then.makeRate, let b = now.makeRate {
                    compareRow("Make rate", then: TodayCard.percent(a), now: TodayCard.percent(b), delta: Int(((b - a) * 100).rounded()))
                }
                ForEach(FormArea.allCases.filter { then.goodRate[$0] != nil && now.goodRate[$0] != nil }) { area in
                    let a = then.goodRate[area] ?? 0, b = now.goodRate[area] ?? 0
                    compareRow(area.title, then: TodayCard.percent(a), now: TodayCard.percent(b),
                               delta: Int(((b - a) * 100).rounded()), symbol: area.symbol)
                }
                Text("Areas show the share of shots graded good.").font(.caption2).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("improvementCard")
        }
        if let focus = log.focus() {
            Card {
                Label("Work on next", systemImage: "scope").font(.caption).foregroundStyle(.secondary)
                Text(focus.title).font(.title3.bold())
                Text(focus.cue).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("progressFocus")
        }
    }

    private func week(_ log: PracticeLog) -> some View {
        let a = log.lastWeek, b = log.thisWeek
        return Card {
            Text("This week vs last week").font(.headline)
            compareRow("Sessions", then: "\(a.sessions)", now: "\(b.sessions)", delta: b.sessions - a.sessions)
            compareRow("Shots", then: "\(a.shots)", now: "\(b.shots)", delta: b.shots - a.shots)
            if let x = a.averageScore, let y = b.averageScore {
                compareRow("Form score", then: "\(x)", now: "\(y)", delta: y - x)
            }
            if let x = a.makeRate, let y = b.makeRate {
                compareRow("Make rate", then: TodayCard.percent(x), now: TodayCard.percent(y), delta: Int(((y - x) * 100).rounded()))
            }
        }
        .accessibilityIdentifier("weekCompare")
    }

    private func bests(_ log: PracticeLog) -> some View {
        Card {
            Text("Personal bests").font(.headline)
            best("Longest streak", "\(log.longestStreak) \(log.longestStreak == 1 ? "day" : "days")", "flame")
            if let shots = log.mostShotsInADay { best("Most shots in a day", "\(shots)", "basketball") }
            if let score = log.bestSessionScore { best("Best session form", "\(score)", "star") }
            if let day = log.bestMakeDay, let rate = day.makeRate {
                best("Best shooting day", "\(TodayCard.percent(rate)) · \(day.day.formatted(.dateTime.month().day()))", "target")
            }
            best("Days practiced", "\(log.practiceDays)", "calendar")
        }
        .accessibilityIdentifier("personalBests")
    }

    private func best(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(Theme.orange).frame(width: 22)
            Text(title)
            Spacer()
            Text(value).bold().monospacedDigit()
        }
        .font(.subheadline)
    }

    private func compareRow(_ title: String, then: String, now: String, delta: Int, symbol: String? = nil) -> some View {
        HStack(spacing: 8) {
            if let symbol { Image(systemName: symbol).foregroundStyle(Theme.orange).frame(width: 22) }
            Text(title)
            Spacer()
            Text(then).monospacedDigit().foregroundStyle(.secondary)
            Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
            Text(now).bold().monospacedDigit()
            Change(delta: delta, unit: "").frame(minWidth: 44, alignment: .trailing)
        }
        .font(.subheadline)
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 12, height: 12)
            Text(text)
        }
    }

    private func stat(_ value: String, _ label: String, symbol: String, id: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: symbol).foregroundStyle(Theme.orange)
            Text(value).font(.title.bold().monospacedDigit()).accessibilityIdentifier(id)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// A signed change, green when up, red when down.
struct Change: View {
    let delta: Int
    let unit: String
    var body: some View {
        Text(delta == 0 ? "±0" : (delta > 0 ? "+\(delta)" : "\(delta)") + unit)
            .font(.caption.bold().monospacedDigit())
            .foregroundStyle(delta > 0 ? .green : delta < 0 ? .red : .secondary)
    }
}
