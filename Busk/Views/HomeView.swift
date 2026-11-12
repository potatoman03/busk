import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(sort: \SessionRecord.date, order: .reverse) private var records: [SessionRecord]
    @State private var showSetup = false
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Button {
                        showSetup = true
                    } label: {
                        Label("Start shooting", systemImage: "figure.basketball")
                            .font(.title3.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("startButton")

                    if let last = records.first {
                        NavigationLink(value: last) {
                            Card {
                                Text("Last session").font(.caption).foregroundStyle(.secondary)
                                SessionRow(record: last)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lastSessionCard")
                    }

                    Card {
                        Text("What Busk coaches").font(.headline)
                        ForEach([FormArea.elbow, .arc, .releaseHeight, .followThrough], id: \.self) { area in
                            Label {
                                VStack(alignment: .leading) {
                                    Text(area.title).bold()
                                    Text(area.cue).font(.subheadline).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: area.symbol).foregroundStyle(Theme.orange)
                            }
                        }
                    }

                    Card {
                        Label("Everything runs on your phone", systemImage: "lock.shield")
                            .font(.subheadline.bold())
                        Text("Body tracking uses Apple's on-device Vision framework. No video is uploaded and nothing needs an account.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(Theme.court.ignoresSafeArea())
            .navigationTitle("Busk")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        HistoryView()
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                    .accessibilityIdentifier("historyButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("settingsButton")
                }
            }
            .navigationDestination(for: SessionRecord.self) { SummaryView(record: $0) }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(isPresented: $showSetup) { SetupFlowView() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your jump shot coach")
                .font(.largeTitle.bold())
            Text("Put your phone on a tripod, step back, and shoot. Busk watches your form and tells you what to fix after every shot.")
                .foregroundStyle(.secondary)
        }
    }
}

struct SessionRow: View {
    let record: SessionRecord
    var body: some View {
        let s = record.summary
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.date, format: .dateTime.weekday().month().day().hour().minute()).font(.headline)
                Text("\(s.count) shots" + (s.topFocus.map { " · focus: \($0.title.lowercased())" } ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(s.averageScore)")
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(Theme.color(forScore: s.averageScore))
        }
    }
}
