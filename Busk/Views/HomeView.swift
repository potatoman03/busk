import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(sort: \SessionRecord.date, order: .reverse) private var records: [SessionRecord]
    @State private var setup: SetupLaunch?
    @State private var showSettings = false
    @Environment(VoiceControl.self) private var voice: VoiceControl?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    Button {
                        setup = SetupLaunch()
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
                        ForEach([FormArea.legs, .setPoint, .elbow, .guideHand, .rhythm, .arc, .releaseTiming, .balance, .followThrough], id: \.self) { area in
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink(value: HomeRoute.history) {
                        // The toolbar draws a Label as its icon alone; spell it out so History is findable.
                        HStack(spacing: 4) {
                            Image(systemName: "clock.arrow.circlepath")
                            Text("History")
                        }
                        .fixedSize()
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
            .navigationDestination(for: HomeRoute.self) { _ in HistoryView() }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(item: $setup) { SetupFlowView(autoStart: $0.autoStart) }
            .safeAreaInset(edge: .bottom) { VoiceDock(commands: [.start]) }
        }
        .onChange(of: voice?.event) { _, event in
            // "Start session" from home skips setup and goes live with the saved camera angle and hand.
            guard event?.command == .start, setup == nil, !showSettings else { return }
            setup = SetupLaunch(autoStart: true)
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

enum HomeRoute: Hashable {
    case history
}

struct SessionRow: View {
    let record: SessionRecord
    var body: some View {
        let s = record.summary
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.date, format: .dateTime.weekday().month().day().hour().minute()).font(.headline)
                Text("\(s.count) \(s.count == 1 ? "shot" : "shots")" + (s.topFocus.map { " · focus: \($0.title.lowercased())" } ?? ""))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(s.averageScore)")
                .font(.title.bold().monospacedDigit())
                .foregroundStyle(Theme.color(forScore: s.averageScore))
        }
    }
}

private struct SetupLaunch: Identifiable {
    let id = UUID()
    var autoStart = false
}
