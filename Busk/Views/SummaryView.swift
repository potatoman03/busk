import SwiftData
import SwiftUI

struct SummaryView: View {
    let record: SessionRecord
    var body: some View {
        SummaryContent(record: record)
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .opaqueNavigationBar()
    }
}

struct SummaryContent: View {
    @Bindable var record: SessionRecord
    @Query(sort: \SessionRecord.date) private var records: [SessionRecord]
    @AppStorage(SettingsKey.dailyShotGoal) private var goal = PracticeGoal.defaultShots
    @Environment(\.dynamicTypeSize) private var typeSize
    private var large: Bool { typeSize.isAccessibilitySize }
    private var summary: SessionSummary { record.summary }
    @State private var lesson: Lesson?

    /// Once the plan has a baseline, the next focus is the plan's, so Summary and Coach never disagree.
    private var nextFocus: (plan: Bool, focus: FormArea?) {
        if !record.isDemo || AppEnvironment.demoCountsForPlan {
            let plan = CoachPlan(sessions: records.coachingSessions)
            if plan.totalShots >= CoachPlan.baselineShots { return (true, plan.focus) }
        }
        return (false, summary.topFocus)
    }

    var body: some View {
        let summary = record.summary
        let previous = records.last { $0.date < record.date && $0.isDemo == record.isDemo }?.summary
        let lastRates = Dictionary(uniqueKeysWithValues: (previous?.areaBreakdown ?? []).map { ($0.area, $0.goodRate) })
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    stat("\(summary.count)", summary.count == 1 ? "shot" : "shots", id: "summaryShotCount")
                    stat(summary.makes.map(String.init) ?? "–", "made", color: .green, id: "summaryMakes")
                    stat("\(summary.averageScore)", "avg form", color: Theme.color(forScore: summary.averageScore), id: "summaryAverage")
                }
                makesCard(summary)
                progressCard(summary)
                if let focus = summary.focus, let r = summary.focusResult {
                    Card {
                        Label("Focus set", systemImage: "scope").font(.caption).foregroundStyle(.secondary)
                        Text(r.measured == 0 ? "\(focus.title): not measured" : "\(focus.title): \(r.good) of \(r.measured) good")
                            .font(.title2.bold())
                            .accessibilityIdentifier("summaryFocusResult")
                        if r.measured > 0 {
                            ProgressView(value: Double(r.good), total: Double(r.measured))
                                .tint(Double(r.good) / Double(r.measured) >= CoachPlan.graduateRate ? .green : .yellow)
                        }
                        Text(r.measured == 0
                             ? "Busk couldn't judge your \(focus.title.lowercased()) from this camera angle."
                             : Double(r.good) / Double(r.measured) >= CoachPlan.graduateRate
                             ? "That's \(Int(CoachPlan.graduateRate * 100))% or better. Keep it there for a few sets and you move on."
                             : "Keep at it: \(Int(CoachPlan.graduateRate * 100))% good over a few sets moves you on. \(focus.cue).")
                            .font(.subheadline).foregroundStyle(.secondary)
                        lessonButton(focus)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("summaryFocus")
                } else if let focus = nextFocus.focus {
                    Card {
                        Label("Next session focus", systemImage: "scope").font(.caption).foregroundStyle(.secondary)
                        Text(focus.title).font(.title2.bold()).accessibilityIdentifier("summaryNextFocus")
                        Text(focus.cue).foregroundStyle(.secondary)
                        lessonButton(focus)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("summaryFocus")
                } else if nextFocus.plan {
                    Card {
                        Label("Next session focus", systemImage: "checkmark.seal").font(.caption).foregroundStyle(.secondary)
                        Text("Nothing to fix right now").font(.title2.bold()).accessibilityIdentifier("summaryNextFocus")
                        Text("Every area Busk measures is solid. Keep shooting: if one slips, Busk makes it your focus.")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("summaryFocus")
                }
                Card {
                    HStack {
                        Text("By area").font(.headline)
                        Spacer()
                        Text(previous != nil ? "last session → now · tap for lesson" : "Tap for the lesson")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !unmeasured.isEmpty {
                        Text("Not measured: " + unmeasured.map(\.title).joined(separator: ", ")
                             + (unmeasured.contains { $0.bestView == .front } && !summary.shots.isEmpty ? ". Set the phone facing you to check them." : ""))
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("summaryUnmeasured")
                    }
                    ForEach(summary.areaBreakdown, id: \.area) { row in
                        Button { lesson = Lesson.forArea(row.area) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            let layout = large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())
                            layout {
                                Label {
                                    Text(row.area.title)
                                } icon: {
                                    Image(systemName: row.area.symbol).foregroundStyle(Theme.orange)
                                }
                                if !large { Spacer() }
                                if let before = lastRates[row.area] {
                                    Text("\(TodayCard.percent(before)) →").monospacedDigit().foregroundStyle(.secondary)
                                        .accessibilityIdentifier("areaLastSession")
                                }
                                Text("\(TodayCard.percent(row.goodRate)) good").monospacedDigit()
                                    .foregroundStyle(lastRates[row.area].map { row.goodRate > $0 + 0.001 ? Color.green : row.goodRate < $0 - 0.001 ? .red : .secondary } ?? .secondary)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                            }
                            ProgressView(value: row.goodRate).tint(row.goodRate >= 0.7 ? .green : row.goodRate >= 0.4 ? .yellow : .red)
                        }
                        .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("summaryArea-\(row.area.rawValue)")
                    }
                }
                Card {
                    Text("Shots").font(.headline)
                    ForEach(Array(summary.shots.enumerated()), id: \.element.id) { i, shot in
                        NavigationLink {
                            ShotDetailView(shot: shot, number: i + 1)
                        } label: {
                            shotRow(shot, number: i + 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("shotRow-\(i + 1)")
                    }
                }
                Text(footer)
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Theme.court.ignoresSafeArea())
        .opaqueNavigationBar()
        .sheet(item: $lesson) { lesson in
            NavigationStack {
                LessonView(lesson: lesson, canPractise: false)
                    .coachDestinations()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { self.lesson = nil } }
                    }
            }
        }
    }

    @ViewBuilder private func lessonButton(_ area: FormArea) -> some View {
        if let l = Lesson.forArea(area) {
            Button { lesson = l } label: { Label("Lesson: \(l.title)", systemImage: "book") }
                .font(.subheadline.bold())
                .accessibilityIdentifier("summaryLessonButton")
        }
    }

    /// Areas no shot was graded on: the front-view checks when filmed side on, or anything tracking lost.
    private var unmeasured: [FormArea] {
        let measured = Set(summary.areaBreakdown.map(\.area))
        return FormArea.allCases.filter { !measured.contains($0) }
    }

    @ViewBuilder private func shotRow(_ shot: ShotResult, number: Int) -> some View {
        let label = Text("#\(number)").monospacedDigit().foregroundStyle(.secondary)
        let score = Text("\(shot.score)").bold().monospacedDigit().foregroundStyle(Theme.color(forScore: shot.score))
        let chevron = Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        Group {
            if large {
                VStack(alignment: .leading, spacing: 4) {
                    HStack { label; Spacer(); score; chevron }
                    Text(shot.cue).multilineTextAlignment(.leading)
                }
            } else {
                HStack {
                    label.frame(minWidth: 34, alignment: .leading)
                    Text(shot.cue).lineLimit(2).multilineTextAlignment(.leading)
                    Spacer()
                    score
                    chevron
                }
            }
        }
        .font(.subheadline)
        .contentShape(Rectangle())
    }

    private var footer: String {
        var parts = ["best shot \(summary.bestScore)", record.date.formatted(date: .abbreviated, time: .shortened)]
        if record.duration >= 1 {
            parts.append(Duration.seconds(record.duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)))
        }
        if record.isDemo { parts.insert("Demo session", at: 0) }
        return parts.joined(separator: " · ")
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
                .lineLimit(1).minimumScaleFactor(0.5)
                .accessibilityIdentifier(id)
            Text(label).font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
