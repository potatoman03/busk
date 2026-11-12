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
                    ForEach(records) { record in
                        NavigationLink(value: record) { SessionRow(record: record) }
                    }
                    .onDelete { idx in idx.map { records[$0] }.forEach(modelContext.delete) }
                }
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("historyList")
            }
        }
        .background(Theme.court.ignoresSafeArea())
        .navigationTitle("History")
        .opaqueNavigationBar()
    }
}
