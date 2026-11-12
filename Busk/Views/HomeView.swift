import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(sort: \SessionRecord.date, order: .reverse) private var records: [SessionRecord]
    @State private var setup: SetupLaunch?
    @State private var showSettings = false
    @Environment(VoiceControl.self) private var voice: VoiceControl?
    @AppStorage(SettingsKey.dailyShotGoal) private var goal = PracticeGoal.defaultShots

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

                    NavigationLink(value: HomeRoute.progress) {
                        TodayCard(log: PracticeLog(records: records), goal: goal)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("todayCard")

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
                        ForEach([FormArea.setPoint, .elbow, .guideHand, .arc, .releaseTiming, .followThrough], id: \.self) { area in
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
                    NavigationLink(value: HomeRoute.history) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("History")
                    .accessibilityIdentifier("historyButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: HomeRoute.progress) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                    }
                    .accessibilityLabel("Progress")
                    .accessibilityIdentifier("progressButton")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                        .accessibilityIdentifier("settingsButton")
                }
            }
            .navigationDestination(for: SessionRecord.self) { SummaryView(record: $0) }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .history: HistoryView()
                case .progress: PracticeProgressView()
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .fullScreenCover(item: $setup) { SetupFlowView(autoStart: $0.autoStart) }
            .safeAreaInset(edge: .bottom) {
                if let voice, voice.state != .off {
                    // Opaque so the list never shows through the bar.
                    VoiceControlBar(commands: [.start])
                        .frame(maxWidth: .infinity)
                        .padding(.top, 10).padding(.bottom, 4)
                        .background(Color(red: 0.03, green: 0.015, blue: 0.01).ignoresSafeArea(edges: .bottom))
                        .overlay(alignment: .top) { Divider() }
                }
            }
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
    case history, progress
}

struct SessionRow: View {
    let record: SessionRecord
    /// History rows sit under a day header, so they only need the time.
    var timeOnly = false
    var body: some View {
        let s = record.summary
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(record.date, format: timeOnly ? .dateTime.hour().minute() : .dateTime.weekday().month().day().hour().minute())
                        .font(.headline)
                    if record.isDemo {
                        Text("Demo").font(.caption2.bold()).padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.secondary.opacity(0.25), in: Capsule())
                            .accessibilityIdentifier("demoTag")
                    }
                }
                Text("\(s.count) shot\(s.count == 1 ? "" : "s")" + (s.makes.map { " · \($0) made" } ?? "") + " · \(record.durationText)")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let focus = s.topFocus {
                    Text("Focus: \(focus.title.lowercased())").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(s.averageScore)")
                    .font(.title.bold().monospacedDigit())
                    .foregroundStyle(Theme.color(forScore: s.averageScore))
                Text("form").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

private struct SetupLaunch: Identifiable {
    let id = UUID()
    var autoStart = false
}
