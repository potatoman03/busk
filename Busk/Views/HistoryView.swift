import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \SessionRecord.date, order: .reverse) private var records: [SessionRecord]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if records.isEmpty {
                ContentUnavailableView("No sessions yet", systemImage: "basketball",
                                       description: Text("Finish a shooting session and it shows up here."))
                    .accessibilityIdentifier("historyEmpty")
            } else {
                List {
                    ForEach(days, id: \.day) { day, sessions in
                        Section {
                            ForEach(sessions) { record in
                                NavigationLink(value: record) { SessionRow(record: record, timeOnly: true) }
                                    .accessibilityIdentifier("historyRow")
                            }
                            .onDelete { idx in idx.map { sessions[$0] }.forEach(modelContext.delete) }
                        } header: {
                            header(day, sessions)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("historyList")
            }
        }
        .background(Theme.court.ignoresSafeArea())
        .navigationTitle("History")
    }

    private var days: [(day: Date, sessions: [SessionRecord])] {
        let calendar = Calendar.current
        return Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
            .map { ($0.key, $0.value.sorted { $0.date > $1.date }) }
            .sorted { $0.day > $1.day }
    }

    private func header(_ day: Date, _ sessions: [SessionRecord]) -> some View {
        let calendar = Calendar.current
        let name = calendar.isDateInToday(day) ? "Today"
            : calendar.isDateInYesterday(day) ? "Yesterday"
            : day.formatted(.dateTime.weekday(.wide).month().day())
        let shots = sessions.reduce(0) { $0 + $1.shots.count }
        let makes = sessions.compactMap(\.summary.makes)
        return HStack {
            Text(name)
            Spacer()
            Text("\(shots) shot\(shots == 1 ? "" : "s")" + (makes.isEmpty ? "" : " · \(makes.reduce(0, +)) made"))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("historyDayHeader")
    }
}
