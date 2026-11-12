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
                    if !unmeasured.isEmpty {
                        Text("Not measured: " + unmeasured.map(\.title).joined(separator: ", "))
                            .font(.footnote).foregroundStyle(.secondary)
                            .accessibilityIdentifier("summaryUnmeasured")
                    }
                    ForEach(summary.areaBreakdown, id: \.area) { row in
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
                            }
                            ProgressView(value: row.goodRate).tint(row.goodRate >= 0.7 ? .green : row.goodRate >= 0.4 ? .yellow : .red)
                        }
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
