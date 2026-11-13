import SwiftUI

/// One shot from a session: its score, the cue it got and how every area graded, worst first.
struct ShotDetailView: View {
    let shot: ShotResult
    let number: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Card {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(shot.score)").font(.largeTitle.bold().monospacedDigit())
                            .foregroundStyle(Theme.color(forScore: shot.score))
                            .accessibilityIdentifier("shotDetailScore")
                        Text("form").foregroundStyle(.secondary)
                        Spacer()
                        if let made = shot.made {
                            Label(made ? "Made" : "Missed", systemImage: made ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(made ? .green : .secondary)
                                .accessibilityIdentifier("shotDetailMade")
                        }
                    }
                    Text(shot.cue).font(.title3.bold())
                    let missing = FormArea.allCases.filter { a in !shot.areas.contains { $0.area == a } }
                    if !missing.isEmpty {
                        Text("Not measured: " + missing.map(\.title).joined(separator: ", "))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Card {
                    Text("By area").font(.headline)
                    ForEach(shot.areas.sorted { $0.grade > $1.grade }, id: \.area) { row in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Theme.color(for: row.grade)).frame(width: 10, height: 10)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(row.area.title) · \(row.grade.label)").bold()
                                Text(row.detail).foregroundStyle(.secondary)
                                if row.grade != .good {
                                    Text(row.area.cue).font(.subheadline).foregroundStyle(Theme.orange)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.court.ignoresSafeArea())
        .navigationTitle("Shot \(number)")
        .navigationBarTitleDisplayMode(.inline)
        .opaqueNavigationBar()
    }
}
