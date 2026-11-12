import SwiftData
import SwiftUI

struct SummaryView: View {
    let record: SessionRecord
    var body: some View {
        SummaryContent(record: record)
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct SummaryContent: View {
    @Bindable var record: SessionRecord
    @Query(sort: \SessionRecord.date) private var records: [SessionRecord]
    @AppStorage(SettingsKey.dailyShotGoal) private var goal = PracticeGoal.defaultShots

    var body: some View {
        let summary = record.summary
        let previous = records.last { $0.date < record.date && $0.isDemo == record.isDemo }?.summary
        let lastRates = Dictionary(uniqueKeysWithValues: (previous?.areaBreakdown ?? []).map { ($0.area, $0.goodRate) })
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    stat("\(summary.count)", "shots", id: "summaryShotCount")
                    stat(summary.makes.map(String.init) ?? "–", "made", color: .green, id: "summaryMakes")
                    stat("\(summary.averageScore)", "avg form", color: Theme.color(forScore: summary.averageScore), id: "summaryAverage")
                }
                makesCard(summary)
                progressCard(summary)
                if let focus = summary.topFocus {
                    Card {
                        Label("Next session focus", systemImage: "scope").font(.caption).foregroundStyle(.secondary)
                        Text(focus.title).font(.title2.bold())
                        Text(focus.cue).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("summaryFocus")
                }
                Card {
                    HStack {
                        Text("By area").font(.headline)
                        Spacer()
                        if previous != nil { Text("last session → now").font(.caption).foregroundStyle(.secondary) }
                    }
                    ForEach(summary.areaBreakdown, id: \.area) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: row.area.symbol).foregroundStyle(Theme.orange).frame(width: 22)
                                Text(row.area.title)
                                Spacer()
                                if let before = lastRates[row.area] {
                                    Text("\(TodayCard.percent(before)) →").monospacedDigit().foregroundStyle(.secondary)
                                        .accessibilityIdentifier("areaLastSession")
                                }
                                Text("\(TodayCard.percent(row.goodRate)) good").monospacedDigit()
                                    .foregroundStyle(lastRates[row.area].map { row.goodRate > $0 + 0.001 ? Color.green : row.goodRate < $0 - 0.001 ? .red : .secondary } ?? .secondary)
                            }
                            ProgressView(value: row.goodRate).tint(row.goodRate >= 0.7 ? .green : row.goodRate >= 0.4 ? .yellow : .red)
                        }
                    }
                }
                Card {
                    Text("Shots").font(.headline)
                    ForEach(Array(summary.shots.enumerated()), id: \.element.id) { i, shot in
                        HStack {
                            Text("#\(i + 1)").monospacedDigit().foregroundStyle(.secondary).frame(width: 34, alignment: .leading)
                            Text(shot.cue).lineLimit(2)
                            Spacer()
                            Text("\(shot.score)").bold().monospacedDigit().foregroundStyle(Theme.color(forScore: shot.score))
                        }
                        .font(.subheadline)
                    }
                }
                Text((record.isDemo ? "Demo session · " : "") + "best shot \(summary.bestScore) · \(record.durationText) · "
                     + record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Theme.court.ignoresSafeArea())
    }

    /// Busk can't see the ball, so makes are logged by the player: live Made/Missed taps, voice, or here afterwards.
    private func makesCard(_ summary: SessionSummary) -> some View {
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Makes").font(.headline)
                    Text(makeRateLine(summary))
                        .font(.subheadline).foregroundStyle(.secondary)
                        .accessibilityIdentifier("summaryMakeRate")
                    if summary.makes != nil, summary.unmarked > 0 {
                        Text("\(summary.unmarked) not marked, so left out. Use − or + to count the whole session.")
                            .font(.caption).foregroundStyle(.secondary)
                            .accessibilityIdentifier("summaryUnmarked")
                    }
                }
                Spacer()
                // Stepping counts makes for the whole session, starting from the live marks.
                Stepper("Makes", value: Binding(get: { summary.makes ?? 0 }, set: { record.makes = $0 }),
                        in: 0...max(summary.count, summary.makes ?? 0))
                    .labelsHidden()
                    .accessibilityIdentifier("makesStepper")
            }
        }
    }

    private func makeRateLine(_ summary: SessionSummary) -> String {
        guard let rate = summary.makeRate else { return "How many went in? Count them here." }
        let n = summary.attempts
        return "\(TodayCard.percent(rate)) of \(n) \(summary.countedWhole ? "" : "marked ")shot\(n == 1 ? "" : "s") went in"
    }

    /// Where this session leaves today's goal and how it compares with earlier sessions.
    @ViewBuilder private func progressCard(_ summary: SessionSummary) -> some View {
        if record.isDemo {
            Card {
                Label("Demo session", systemImage: "play.rectangle").font(.headline)
                Text("The built-in shooter took these shots, so they don't count toward your streak, daily goal or progress.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("summaryDemoNote")
        } else {
            dayCard(summary)
        }
    }

    private func dayCard(_ summary: SessionSummary) -> some View {
        let log = PracticeLog(records: records)
        let day = log.day(record.date)
        let earlierRecords = records.filter { $0.date < record.date && !$0.isDemo }.suffix(5)
        let earlier = earlierRecords.flatMap(\.shots)
        return Card {
            HStack(spacing: 14) {
                GoalRing(value: day.shots, goal: goal).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Calendar.current.isDateInToday(record.date) ? "Today" : record.date.formatted(.dateTime.weekday(.wide)))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(day.shots) of \(goal) shots").font(.headline.monospacedDigit())
                        .accessibilityIdentifier("summaryDayShots")
                    if log.currentStreak > 0 && Calendar.current.isDateInToday(record.date) {
                        Label("\(log.currentStreak) day streak", systemImage: "flame.fill").font(.caption).foregroundStyle(Theme.orange)
                    }
                }
                Spacer()
                if !earlier.isEmpty {
                    let before = SessionSummary(shots: Array(earlier)).averageScore
                    VStack(alignment: .trailing, spacing: 2) {
                        Change(delta: summary.averageScore - before, unit: "").font(.title3)
                        Text("form vs last \(earlierRecords.count)").font(.caption2).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("summaryFormChange")
                }
            }
        }
    }

    private func stat(_ value: String, _ label: String, color: Color = .primary, id: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.largeTitle.bold().monospacedDigit()).foregroundStyle(color)
                .accessibilityIdentifier(id)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
