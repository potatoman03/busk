import SwiftUI

struct SummaryView: View {
    let record: SessionRecord
    var body: some View {
        SummaryContent(summary: record.summary, date: record.date, isDemo: record.isDemo)
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct SummaryContent: View {
    let summary: SessionSummary
    let date: Date
    let isDemo: Bool
    @State private var lesson: Lesson?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    stat("\(summary.count)", "shots", id: "summaryShotCount")
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
                } else if let focus = summary.topFocus {
                    Card {
                        Label("Next session focus", systemImage: "scope").font(.caption).foregroundStyle(.secondary)
                        Text(focus.title).font(.title2.bold())
                        Text(focus.cue).foregroundStyle(.secondary)
                        lessonButton(focus)
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
                    ForEach(summary.areaBreakdown, id: \.area) { row in
                        Button { lesson = Lesson.forArea(row.area) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: row.area.symbol).foregroundStyle(Theme.orange).frame(width: 22)
                                    Text(row.area.title)
                                    Spacer()
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
                    let unseen = FormArea.allCases.filter { a in !summary.areaBreakdown.contains { $0.area == a } }
                    if !unseen.isEmpty, !summary.shots.isEmpty {
                        Text("Not judged from this angle: " + unseen.map(\.title).joined(separator: ", ")
                             + (unseen.contains { $0.bestView == .front } ? ". Set the phone facing you to check them." : "."))
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("summaryUnseenAreas")
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
                Text((isDemo ? "Demo session · " : "") + date.formatted(date: .abbreviated, time: .shortened))
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
    }

    @ViewBuilder private func lessonButton(_ area: FormArea) -> some View {
        if let l = Lesson.forArea(area) {
            Button { lesson = l } label: { Label("Lesson: \(l.title)", systemImage: "book") }
                .font(.subheadline.bold())
                .accessibilityIdentifier("summaryLessonButton")
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
