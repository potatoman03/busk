import SwiftData
import SwiftUI

/// The player's coaching plan: today's workout, the current focus, and how each part of the shot is going.
struct CoachView: View {
    @Query(sort: \SessionRecord.date) private var records: [SessionRecord]
    @AppStorage(SettingsKey.hasBall) private var hasBall = false
    @State private var done: Set<String> = WorkoutChecklist.done()
    @State private var launch: FocusLaunch?
    @State private var showGuide = false

    private var plan: CoachPlan { CoachPlan(sessions: records.map(\.practice)) }

    var body: some View {
        let plan = plan
        let steps = plan.workout(hasBall: hasBall)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                focusCard(plan)
                Picker("Equipment", selection: $hasBall) {
                    Text("No ball").tag(false)
                    Text("I have a ball").tag(true)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("hasBallPicker")

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Today's workout").font(.headline)
                        Spacer()
                        Text("\(steps.filter { isDone($0) }.count)/\(steps.count)")
                            .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            .accessibilityIdentifier("workoutProgress")
                    }
                    ForEach(steps) { step in stepRow(step) }
                }

                progressCard(plan)

                NavigationLink(value: CoachRoute.library) {
                    Card {
                        Label("All lessons and drills", systemImage: "books.vertical").font(.headline)
                        Text("\(Lesson.all.count) lessons, \(Drill.all.count) drills, \(Drill.all.filter { !$0.needsBall }.count) of them without a ball.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("libraryLink")
            }
            .padding(20)
        }
        .background(Theme.court.ignoresSafeArea())
        .navigationTitle("Coach")
        .toolbar {
            Button { showGuide = true } label: { Image(systemName: "questionmark.circle") }
                .accessibilityLabel("How Busk works")
                .accessibilityIdentifier("guideButton")
        }
        .sheet(isPresented: $showGuide) { GuideView() }
        .onAppear { done = WorkoutChecklist.done() }
        .fullScreenCover(item: $launch, onDismiss: { done = WorkoutChecklist.done() }) {
            SetupFlowView(focus: $0.focus, targetShots: $0.shots)
        }
    }

    // MARK: - Focus

    private func focusCard(_ plan: CoachPlan) -> some View {
        Card {
            if let focus = plan.focus, let p = plan.progress(for: focus) {
                Label("Your focus", systemImage: "scope").font(.caption).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text(focus.title).font(.title.bold()).accessibilityIdentifier("coachFocus")
                    Spacer()
                    StageBadge(stage: p.stage)
                }
                Text(focus.cue).foregroundStyle(Theme.orange)
                if let reason = plan.focusReason {
                    Text(reason).font(.subheadline).foregroundStyle(.secondary)
                }
                if p.measured >= CoachPlan.minimumToJudge {
                    ProgressView(value: min(p.goodRate / CoachPlan.graduateRate, 1)) {
                        Text("\(Int((p.goodRate * 100).rounded()))% good · goal \(Int(CoachPlan.graduateRate * 100))%")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tint(Theme.orange)
                }
            } else {
                Label("Getting started", systemImage: "sparkles").font(.caption).foregroundStyle(.secondary)
                Text("Let's find your first focus").font(.title2.bold()).accessibilityIdentifier("coachFocus")
                Text(plan.totalShots == 0
                     ? "Learn the four beats of a jump shot, then take \(CoachPlan.baselineShots)+ shots. Busk picks the one thing to fix first and builds your plan around it."
                     : "\(plan.totalShots) of \(CoachPlan.baselineShots) baseline shots done. A few more and Busk picks your focus.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if !plan.graduated.isEmpty {
                Label("Mastered: " + plan.graduated.map(\.title).joined(separator: ", "), systemImage: "checkmark.seal.fill")
                    .font(.footnote).foregroundStyle(.green)
                    .accessibilityIdentifier("graduatedAreas")
            }
        }
        .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("focusCard")
    }

    // MARK: - Workout

    private func isDone(_ step: WorkoutStep) -> Bool {
        WorkoutChecklist.isDone(step, checked: done, sessions: records.map(\.practice))
    }

    private func toggle(_ step: WorkoutStep) {
        let now = !done.contains(step.id)
        WorkoutChecklist.set(step.id, done: now)
        done = WorkoutChecklist.done()
    }

    @ViewBuilder private func stepRow(_ step: WorkoutStep) -> some View {
        let complete = isDone(step)
        HStack(spacing: 12) {
            Button { toggle(step) } label: {
                Image(systemName: complete ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(complete ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(complete ? "Mark \(step.title) not done" : "Mark \(step.title) done")
            .accessibilityIdentifier("check-\(step.id)")

            switch step.kind {
            case .lesson(let lesson):
                NavigationLink(value: CoachRoute.lesson(lesson.id)) { stepLabel(step, complete: complete) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("step-\(step.id)")
            case .drill(let drill):
                NavigationLink(value: CoachRoute.drill(drill.id)) { stepLabel(step, complete: complete) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("step-\(step.id)")
            case .trackedSet(let focus, let shots):
                Button { launch = FocusLaunch(focus: focus, shots: shots) } label: { stepLabel(step, complete: complete, go: true) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("step-\(step.id)")
            }
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func stepLabel(_ step: WorkoutStep, complete: Bool, go: Bool = false) -> some View {
        HStack(spacing: 12) {
            Image(systemName: step.symbol).foregroundStyle(Theme.orange).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).font(.subheadline.bold()).strikethrough(complete, color: .secondary)
                Text(step.detail).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: go ? "play.circle.fill" : "chevron.right")
                .foregroundStyle(go ? Theme.orange : .secondary)
                .font(go ? .title2 : .footnote)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Progress

    private func progressCard(_ plan: CoachPlan) -> some View {
        Card {
            Text("Your shot, part by part").font(.headline)
            Text("From your last \(CoachPlan.window) shots that showed each part.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(plan.areas) { p in
                NavigationLink(value: CoachRoute.lesson(Lesson.forArea(p.area)?.id ?? "overview")) {
                    HStack {
                        Image(systemName: p.area.symbol).foregroundStyle(Theme.orange).frame(width: 24)
                        Text(p.area.title)
                        if p.area == plan.focus {
                            Image(systemName: "scope").font(.caption).foregroundStyle(Theme.orange)
                        }
                        Spacer()
                        if let trend = p.trend, trend != 0, p.stage != .unmeasured {
                            Text(trend > 0 ? "+\(trend)" : "\(trend)")
                                .font(.caption.monospacedDigit()).foregroundStyle(trend > 0 ? .green : .red)
                        }
                        if p.stage != .unmeasured {
                            Text("\(Int((p.goodRate * 100).rounded()))%").font(.subheadline.monospacedDigit())
                        }
                        StageBadge(stage: p.stage)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("area-\(p.area.rawValue)")
            }
        }
    }
}

struct StageBadge: View {
    let stage: AreaProgress.Stage
    var body: some View {
        Text(stage.label)
            .font(.caption2.bold())
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.2), in: Capsule())
            .foregroundStyle(color)
    }
    private var color: Color {
        switch stage {
        case .unmeasured: return .secondary
        case .learning: return .red
        case .building: return .yellow
        case .solid: return .green
        case .lockedIn: return .mint
        }
    }
}

enum CoachRoute: Hashable {
    case plan, library
    case lesson(String)
    case drill(String)
}

private struct FocusLaunch: Identifiable {
    let id = UUID()
    let focus: FormArea?
    let shots: Int
}

/// Destinations for coaching routes; attach once to a NavigationStack.
struct CoachDestinations: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: CoachRoute.self) { route in
            switch route {
            case .plan: CoachView()
            case .library: LibraryView()
            case .lesson(let id): Lesson.byID(id).map { LessonView(lesson: $0) }
            case .drill(let id): Drill.byID(id).map { DrillView(drill: $0) }
            }
        }
    }
}

extension View {
    func coachDestinations() -> some View { modifier(CoachDestinations()) }
}
