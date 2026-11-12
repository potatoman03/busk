import SwiftUI

struct LessonView: View {
    let lesson: Lesson
    /// Whether the lesson can start a focus set (not from inside a running session).
    var canPractise = true
    @State private var launch: Launch?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lesson.unit.title.uppercased()).font(.caption.bold()).foregroundStyle(Theme.orange)
                    Text(lesson.title).font(.largeTitle.bold()).accessibilityIdentifier("lessonTitle")
                    Text(lesson.summary).foregroundStyle(.secondary)
                }

                Card {
                    Label("Why it matters", systemImage: "lightbulb").font(.headline)
                    Text(lesson.why)
                }

                if lesson.id == "overview" || lesson.id == "setPoint" {
                    Card {
                        Label("What it looks like", systemImage: "figure.basketball").font(.headline)
                        BallPositionsPicture()
                    }
                }

                Card {
                    Label("How to do it", systemImage: "list.number").font(.headline)
                    ForEach(Array(lesson.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.orange)
                            Text(step)
                        }
                    }
                }

                Card {
                    Label("Think this", systemImage: "quote.bubble").font(.headline)
                    Text("“\(lesson.feel)”").font(.title3.italic())
                }

                if !lesson.mistakes.isEmpty {
                    Card {
                        Label("Common mistakes", systemImage: "exclamationmark.triangle").font(.headline)
                        ForEach(lesson.mistakes, id: \.self) { m in
                            Label { Text(m) } icon: { Image(systemName: "xmark.circle").foregroundStyle(.red) }
                        }
                    }
                }

                if let checks = lesson.howBuskChecks {
                    Card {
                        Label("How Busk checks it", systemImage: "camera.viewfinder").font(.headline)
                        Text(checks).font(.subheadline).foregroundStyle(.secondary)
                    }
                }

                if !lesson.drills.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Drills").font(.headline)
                        ForEach(lesson.drills) { drill in
                            NavigationLink(value: CoachRoute.drill(drill.id)) { DrillRow(drill: drill) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("drill-\(drill.id)")
                        }
                    }
                }

                if canPractise, let area = lesson.area {
                    Button { launch = Launch(focus: area) } label: {
                        Label("Practise it: \(CoachPlan.focusSetShots)-shot focus set", systemImage: "scope")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityIdentifier("practiseLessonButton")
                }
            }
            .padding(20)
        }
        .background(Theme.court.ignoresSafeArea())
        .navigationTitle(lesson.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { WorkoutChecklist.set("lesson-\(lesson.id)", done: true) }
        .fullScreenCover(item: $launch) { SetupFlowView(focus: $0.focus, targetShots: CoachPlan.focusSetShots) }
    }

    private struct Launch: Identifiable {
        let id = UUID()
        let focus: FormArea
    }
}

struct DrillView: View {
    let drill: Drill
    @State private var done = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(drill.title).font(.largeTitle.bold()).accessibilityIdentifier("drillTitle")
                    Text(drill.summary).foregroundStyle(.secondary)
                    HStack {
                        Pill(text: drill.needsBall ? "Needs a ball" : "No ball needed",
                             systemImage: drill.needsBall ? "basketball" : "figure.run")
                        Pill(text: drill.dose, systemImage: "repeat")
                    }
                }

                Card {
                    Label("Steps", systemImage: "list.number").font(.headline)
                    ForEach(Array(drill.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(Theme.orange)
                            Text(step)
                        }
                    }
                }

                Card {
                    Label("Builds", systemImage: "figure.basketball").font(.headline)
                    ForEach(drill.areas, id: \.self) { area in
                        Label(area.title, systemImage: area.symbol)
                    }
                    if drill.tracked {
                        Text("Set the phone up and Busk can watch this one: start a session and do the reps in view.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }

                Button {
                    done.toggle()
                    WorkoutChecklist.set("drill-\(drill.id)", done: done)
                    if Self.warmUps.contains(drill.id) { WorkoutChecklist.set("warmup", done: done) }
                } label: {
                    Label(done ? "Done today" : "Mark done", systemImage: done ? "checkmark.circle.fill" : "circle")
                        .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(done ? .green : Theme.orange)
                .accessibilityIdentifier("drillDoneButton")
            }
            .padding(20)
        }
        .background(Theme.court.ignoresSafeArea())
        .navigationTitle(drill.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { done = WorkoutChecklist.done().contains("drill-\(drill.id)") }
    }

    private static let warmUps: Set<String> = ["shadow", "formShooting"]
}

struct DrillRow: View {
    let drill: Drill
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: drill.needsBall ? "basketball" : "figure.run").foregroundStyle(Theme.orange).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(drill.title).font(.subheadline.bold())
                Text((drill.needsBall ? "" : "No ball · ") + drill.dose).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.footnote).foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Every lesson, by unit, and every drill.
struct LibraryView: View {
    @AppStorage(SettingsKey.hasBall) private var hasBall = false

    var body: some View {
        List {
            ForEach(Lesson.Unit.allCases, id: \.self) { unit in
                Section(unit.title) {
                    ForEach(Lesson.all.filter { $0.unit == unit }) { lesson in
                        NavigationLink(value: CoachRoute.lesson(lesson.id)) {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lesson.title).bold()
                                    Text(lesson.summary).font(.footnote).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: lesson.area?.symbol ?? "figure.basketball").foregroundStyle(Theme.orange)
                            }
                        }
                        .accessibilityIdentifier("lesson-\(lesson.id)")
                    }
                }
            }
            Section(hasBall ? "Drills" : "Drills (no-ball first)") {
                ForEach(hasBall ? Drill.all : Drill.all.filter { !$0.needsBall } + Drill.all.filter(\.needsBall)) { drill in
                    NavigationLink(value: CoachRoute.drill(drill.id)) {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(drill.title).bold()
                                Text((drill.needsBall ? "Ball · " : "No ball · ") + drill.dose)
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: drill.needsBall ? "basketball" : "figure.run").foregroundStyle(Theme.orange)
                        }
                    }
                    .accessibilityIdentifier("libraryDrill-\(drill.id)")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.court.ignoresSafeArea())
        .navigationTitle("Lessons")
    }
}

/// Side-on figures of where the ball goes: the shooting pocket, the set point, and the chest push to avoid.
struct BallPositionsPicture: View {
    struct Panel: Identifiable {
        let id: String
        let title: String
        let example: String
        let style: ShotSimulator.Style
        let time: Double
        let good: Bool
    }

    static let panels = [
        Panel(id: "pocket", title: "Shooting pocket", example: "Ball at your waist on your shooting side, knees bent",
              style: .good, time: 0.40, good: true),
        Panel(id: "setPoint", title: "Set point", example: "Just above your forehead. You see the rim under the ball",
              style: .good, time: 0.70, good: true),
        Panel(id: "chest", title: "Not this", example: "From your chest, like a pass",
              style: .lowSet, time: 0.70, good: false),
    ]

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(Self.panels) { panel in
                VStack(spacing: 6) {
                    PoseFigure(pose: Self.pose(panel), color: panel.good ? .white : .red.opacity(0.85))
                        .frame(height: 130)
                    Label(panel.title, systemImage: panel.good ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.caption.bold())
                        .foregroundStyle(panel.good ? Color.green : Color.red)
                        .labelStyle(.titleAndIcon)
                    Text(panel.example).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("ballPosition-\(panel.id)")
            }
        }
    }

    /// A demo-shooter pose with the shooting arm placed by hand, so the ball sits exactly where the panel says.
    static func pose(_ panel: Panel) -> PoseFrame {
        let frames = ShotSimulator().frames(for: panel.style)
        var pose = frames[min(frames.count - 1, Int(panel.time * 30))]
        guard let shoulder = pose[.rightShoulder], let hip = pose[.rightHip] else { return pose }
        let elbow: CGPoint, wrist: CGPoint, ball: CGPoint
        switch panel.id {
        case "pocket":
            elbow = CGPoint(x: shoulder.x - 0.01, y: shoulder.y + 0.105)
            wrist = CGPoint(x: elbow.x + 0.07, y: hip.y - 0.02)
            ball = CGPoint(x: wrist.x + 0.035, y: wrist.y - 0.015)
        case "chest":
            elbow = CGPoint(x: shoulder.x + 0.01, y: shoulder.y + 0.10)
            wrist = CGPoint(x: elbow.x + 0.09, y: elbow.y - 0.035)
            ball = CGPoint(x: wrist.x + 0.035, y: wrist.y - 0.01)
        default:
            guard let w = pose[.rightWrist] else { return pose }
            pose.ball = Ball(center: CGPoint(x: w.x + 0.012, y: w.y - 0.03), radius: 0.03)
            return pose
        }
        pose.joints[.rightElbow] = elbow
        pose.joints[.rightWrist] = wrist
        pose.ball = Ball(center: ball, radius: 0.03)
        return pose
    }
}

struct PoseFigure: View {
    let pose: PoseFrame
    var color: Color = .white

    var body: some View {
        Canvas { ctx, size in
            guard let wrist = pose[.rightWrist] else { return }
            let ball = pose.ball?.center ?? CGPoint(x: wrist.x + 0.012, y: wrist.y - 0.03), radius = pose.ball?.radius ?? 0.03
            let points = Array(pose.joints.values) + [CGPoint(x: ball.x, y: ball.y - radius), CGPoint(x: ball.x + radius, y: ball.y)]
            let minX = points.map(\.x).min()!, maxX = points.map(\.x).max()!
            let minY = points.map(\.y).min()!, maxY = points.map(\.y).max()!
            let scale = min(size.width / max(maxX - minX, 0.3), size.height / (maxY - minY)) * 0.92
            let ox = size.width / 2 - (minX + maxX) / 2 * scale, oy = size.height / 2 - (minY + maxY) / 2 * scale
            func map(_ p: CGPoint) -> CGPoint { CGPoint(x: ox + p.x * scale, y: oy + p.y * scale) }
            for (a, b) in SkeletonOverlay.bones {
                guard let pa = pose[a], let pb = pose[b] else { continue }
                var path = Path()
                path.move(to: map(pa))
                path.addLine(to: map(pb))
                ctx.stroke(path, with: .color(color.opacity(0.85)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            if let nose = pose[.nose] {
                let c = map(nose), r = 0.025 * scale
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color), lineWidth: 3)
            }
            let c = map(ball), r = radius * scale
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(Theme.orange))
        }
        .accessibilityHidden(true)
    }
}
