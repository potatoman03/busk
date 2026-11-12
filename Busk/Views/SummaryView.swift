import SwiftData
import SwiftUI

struct SummaryView: View {
    let record: SessionRecord
    var body: some View {
        SummaryContent(summary: record.summary, date: record.date, isDemo: record.isDemo, duration: record.duration)
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .opaqueNavigationBar()
    }
}

struct SummaryContent: View {
    let summary: SessionSummary
    let date: Date
    let isDemo: Bool
    @State private var lesson: Lesson?
    @Query(sort: \SessionRecord.date) private var records: [SessionRecord]

    /// Once the plan has a baseline, the next focus is the plan's, so Summary and Coach never disagree.
    private var nextFocus: (plan: Bool, focus: FormArea?) {
        if !isDemo || AppEnvironment.demoCountsForPlan {
            let plan = CoachPlan(sessions: records.coachingSessions)
            if plan.totalShots >= CoachPlan.baselineShots { return (true, plan.focus) }
        }
        return (false, summary.topFocus)
    }
    var duration: TimeInterval?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var large: Bool { typeSize.isAccessibilitySize }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    stat("\(summary.count)", summary.count == 1 ? "shot" : "shots", id: "summaryShotCount")
                    stat("\(summary.averageScore)", "avg form", color: Theme.color(forScore: summary.averageScore), id: "summaryAverage")
                    stat("\(summary.bestScore)", "best", id: "summaryBest")
                }
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
                        Text("Tap for the lesson").font(.caption).foregroundStyle(.secondary)
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
                                    Text("\(Int((row.goodRate * 100).rounded()))% good").monospacedDigit().foregroundStyle(.secondary)
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
        .sheet(item: $lesson) { lesson in
            NavigationStack {
                LessonView(lesson: lesson, canPractise: false)
                    .coachDestinations()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { self.lesson = nil } }
                    }
            }
        }
        .opaqueNavigationBar()
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
        var parts = [date.formatted(date: .abbreviated, time: .shortened)]
        if let duration, duration >= 1 {
            parts.append(Duration.seconds(duration).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2)))
        }
        if isDemo { parts.insert("Demo session", at: 0) }
        return parts.joined(separator: " · ")
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
