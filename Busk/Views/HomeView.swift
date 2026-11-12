import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(sort: \SessionRecord.date, order: .reverse) private var records: [SessionRecord]
    @AppStorage(SettingsKey.hasBall) private var hasBall = false
    @State private var setup: SetupLaunch?
    @State private var showSettings = false
    @State private var showGuide = false
    @AppStorage(SettingsKey.hasSeenSetupTips) private var hasSeenGuide = false
    @State private var checkedSteps = WorkoutChecklist.done()
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

                    coachCard

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
                        HStack {
                            Text("What Busk coaches").font(.headline)
                            Spacer()
                            NavigationLink("All lessons", value: CoachRoute.library)
                                .font(.subheadline).tint(Theme.orange)
                                .accessibilityIdentifier("lessonsLink")
                        }
                        ForEach(CoachPlan.order, id: \.self) { area in
                            NavigationLink(value: CoachRoute.lesson(Lesson.forArea(area)?.id ?? "overview")) {
                                HStack {
                                    Label {
                                        VStack(alignment: .leading) {
                                            Text(area.title).bold()
                                            Text(area.cue).font(.subheadline).foregroundStyle(.secondary)
                                                .multilineTextAlignment(.leading)
                                        }
                                    } icon: {
                                        Image(systemName: area.symbol).foregroundStyle(Theme.orange)
                                    }
                                    Spacer(minLength: 4)
                                    if let view = area.bestView {
                                        Text(view.label).font(.caption2).foregroundStyle(.secondary)
                                    }
                                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("homeArea-\(area.rawValue)")
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
            .opaqueNavigationBar()
            .toolbar {
                // "Busk" stays the back-button title; the header below is the only heading on screen.
                ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
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
            .coachDestinations()
            .sheet(isPresented: $showSettings) { SettingsView() }
            .sheet(isPresented: $showGuide) { GuideView() }
            .onAppear { checkedSteps = WorkoutChecklist.done() }
            .task {
                // UI tests start on Home unless they ask for the first-run guide.
                if !hasSeenGuide && (!AppEnvironment.isUITesting || AppEnvironment.arguments.contains("-show-guide")) {
                    showGuide = true
                }
            }
            .fullScreenCover(item: $setup) { SetupFlowView(autoStart: $0.autoStart) }
            .safeAreaInset(edge: .bottom) { VoiceDock(commands: [.start]) }
        }
        .onChange(of: voice?.event) { _, event in
            // "Start session" from home skips setup and goes live with the saved camera angle and hand.
            guard event?.command == .start, setup == nil, !showSettings else { return }
            setup = SetupLaunch(autoStart: true)
        }
    }

    /// Today's plan at a glance; opens the full coaching plan.
    private var coachCard: some View {
        let plan = CoachPlan(sessions: records.coachingSessions)
        let steps = plan.workout(hasBall: hasBall)
        let sessions = records.coachingSessions
        let next = steps.first { !WorkoutChecklist.isDone($0, checked: checkedSteps, sessions: sessions) }
        return NavigationLink(value: CoachRoute.plan) {
            Card {
                HStack {
                    Label("Your coach", systemImage: "graduationcap").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
                }
                Text(plan.focus.map { "Focus: \($0.title)" } ?? (plan.totalShots >= CoachPlan.baselineShots ? "Nothing to fix right now" : "Find your first focus"))
                    .font(.title3.bold())
                    .accessibilityIdentifier("homeCoachFocus")
                if let next {
                    Label("Next: \(next.title)", systemImage: next.symbol)
                        .font(.subheadline).foregroundStyle(Theme.orange)
                } else {
                    Label("Today's workout done", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("coachCard")
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
                if let focus = record.focus {
                    Text("Focus set: \(focus.title.lowercased())").font(.caption).foregroundStyle(.secondary)
                } else if !record.isDemo || AppEnvironment.demoCountsForPlan, let focus = s.topFocus {
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
