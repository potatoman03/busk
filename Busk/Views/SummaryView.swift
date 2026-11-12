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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    stat("\(summary.count)", "shots", id: "summaryShotCount")
                    stat("\(summary.averageScore)", "avg form", color: Theme.color(forScore: summary.averageScore), id: "summaryAverage")
                    stat("\(summary.bestScore)", "best", id: "summaryBest")
                }
                if let focus = summary.topFocus {
                    Card {
                        Label("Next session focus", systemImage: "scope").font(.caption).foregroundStyle(.secondary)
                        Text(focus.title).font(.title2.bold())
                        Text(focus.cue).foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("summaryFocus")
                }
                Card {
                    Text("By area").font(.headline)
                    ForEach(summary.areaBreakdown, id: \.area) { row in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Image(systemName: row.area.symbol).foregroundStyle(Theme.orange).frame(width: 22)
                                Text(row.area.title)
                                Spacer()
                                Text("\(Int((row.goodRate * 100).rounded()))% good").monospacedDigit().foregroundStyle(.secondary)
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
                Text((isDemo ? "Demo session · " : "") + date.formatted(date: .abbreviated, time: .shortened))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Theme.court.ignoresSafeArea())
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
