import XCTest
@testable import Busk

final class CoachPlanTests: XCTestCase {
    private let metrics = ShotMetrics(view: .front, setPointHeight: 0.15, elbowFlare: 0.02, armAngle: nil, followThrough: 0.8,
                                      legDrive: 0.04, releaseTiming: 0, hitch: 0, drift: 0.02, guideHandPush: 0.01)

    /// A shot graded good everywhere except the given areas.
    private func shot(_ grades: [FormArea: Grade] = [:], areas: [FormArea] = [.setPoint, .legs, .balance, .elbow, .guideHand]) -> ShotResult {
        ShotResult(metrics: metrics,
                   areas: areas.map { AreaResult(area: $0, grade: grades[$0] ?? .good, value: 0, detail: "") },
                   score: 80, cue: "", focus: nil)
    }

    private func session(_ shots: [ShotResult], focus: FormArea? = nil, daysAgo: Int = 0) -> PracticeSession {
        PracticeSession(date: Date().addingTimeInterval(TimeInterval(-daysAgo * 86_400)), focus: focus, shots: shots)
    }

    func testNoFocusBeforeBaseline() {
        let plan = CoachPlan(sessions: [session(Array(repeating: shot([.elbow: .needsWork]), count: 5))])
        XCTAssertNil(plan.focus)
        let steps = plan.workout(hasBall: false)
        XCTAssertEqual(steps.map(\.id), ["lesson-overview", "baseline"])
        XCTAssertTrue(steps[1].title.contains("shadow"))
    }

    func testFocusIsAreaThatNeedsWorkMost() {
        let shots = Array(repeating: shot([.elbow: .needsWork, .legs: .ok]), count: 8)
            + Array(repeating: shot([.guideHand: .needsWork]), count: 8)
        XCTAssertEqual(CoachPlan(sessions: [session(shots)]).focus, .elbow)
    }

    func testTiesGoByCoachingPriority() {
        let shots = Array(repeating: shot([.elbow: .needsWork, .legs: .needsWork]), count: 15)
        XCTAssertEqual(CoachPlan(sessions: [session(shots)]).focus, .legs)
        let set = Array(repeating: shot([.setPoint: .needsWork, .legs: .needsWork]), count: 15)
        XCTAssertEqual(CoachPlan(sessions: [session(set)]).focus, .setPoint, "Set point ranks before legs, as live")
    }

    /// A beginner pushing from the chest: the plan's focus is the fix the live cue and the summary lead with.
    func testFocusMatchesTheLiveCueForAChestPush() throws {
        var sim = ShotSimulator()
        sim.view = .side
        let analyzer = ShotAnalyzer(handedness: .right, view: .side)
        var frames = sim.idleFrames(seconds: 0.5, start: 0)
        for _ in 0..<CoachPlan.baselineShots {
            let shot = sim.frames(for: .lowSet, start: frames.last!.timestamp + 1 / sim.fps)
            frames += shot + sim.idleFrames(seconds: 1.5, start: shot.last!.timestamp + 1 / sim.fps)
        }
        let results = frames.compactMap { analyzer.process($0) }.map { FormEvaluator().evaluate($0) }
        XCTAssertEqual(results.count, CoachPlan.baselineShots)
        let live = try XCTUnwrap(SessionSummary(shots: results).topFocus)
        XCTAssertEqual(live, .setPoint)
        XCTAssertEqual(CoachPlan(sessions: [session(results)]).focus, live)
    }

    func testPlanFollowsShotsLeadFixOverMoreFrequentMarginalFlaw() {
        // Legs is graded needs-work on every shot (marginal), but each shot led with the set point.
        let shots = (0..<15).map { _ -> ShotResult in
            var r = shot([.legs: .needsWork, .setPoint: .needsWork])
            r.focus = .setPoint
            return r
        } + (0..<5).map { _ in var r = shot([.legs: .needsWork]); r.focus = .legs; return r }
        XCTAssertEqual(CoachPlan(sessions: [session(shots)]).focus, .setPoint)
    }

    func testBaselineSetIsDoneOnlyAtItsTarget() {
        let partial = [session(Array(repeating: shot(), count: 6))]
        let plan = CoachPlan(sessions: partial)
        let baseline = try! XCTUnwrap(plan.workout(hasBall: false).first { $0.id == "baseline" })
        XCTAssertEqual(baseline.title, "Baseline: \(CoachPlan.baselineShots) shadow shots")
        XCTAssertFalse(WorkoutChecklist.isDone(baseline, checked: [], sessions: partial))
        let split = [session(Array(repeating: shot(), count: 8)), session(Array(repeating: shot(), count: 7))]
        XCTAssertTrue(WorkoutChecklist.isDone(baseline, checked: [], sessions: split))
        let focusSet = WorkoutStep(id: "focus-legs", kind: .trackedSet(focus: .legs, shots: 20), title: "", detail: "")
        XCTAssertFalse(WorkoutChecklist.isDone(focusSet, checked: [], sessions: [session(Array(repeating: shot(), count: 12), focus: .legs)]))
        XCTAssertTrue(WorkoutChecklist.isDone(focusSet, checked: [], sessions: [session(Array(repeating: shot(), count: 20), focus: .legs)]))
    }

    func testFlawOutsideTheFocusIsCalledOut() {
        func r(_ grades: [FormArea: Grade], focus: FormArea?) -> ShotResult {
            var s = shot(grades); s.focus = focus; return s
        }
        XCTAssertEqual(CoachSession.outranksFocus(.legs, in: r([.setPoint: .needsWork], focus: .setPoint)), .setPoint)
        XCTAssertEqual(CoachSession.outranksFocus(.legs, in: r([.setPoint: .needsWork, .legs: .needsWork], focus: .setPoint)), .setPoint)
        XCTAssertNil(CoachSession.outranksFocus(.setPoint, in: r([.setPoint: .needsWork, .legs: .needsWork], focus: .setPoint)))
        XCTAssertNil(CoachSession.outranksFocus(.setPoint, in: r([.legs: .needsWork, .setPoint: .needsWork], focus: .legs)),
                     "A lower-priority flaw doesn't interrupt a focus that still needs work")
        XCTAssertNil(CoachSession.outranksFocus(.legs, in: r([:], focus: nil)))
    }

    func testDemoSessionsDontBuildAPlan() throws {
        try XCTSkipIf(AppEnvironment.demoCountsForPlan)
        let shots = Array(repeating: shot([.setPoint: .needsWork]), count: 13)
        let demo = SessionRecord(date: Date(), duration: 60, view: .side, handedness: .right, isDemo: true, shots: shots)
        let real = SessionRecord(date: Date(), duration: 60, view: .side, handedness: .right, isDemo: false, shots: shots)
        let plan = CoachPlan(sessions: [demo].coachingSessions)
        XCTAssertEqual(plan.totalShots, 0)
        XCTAssertNil(plan.focus)
        XCTAssertEqual([demo, real].coachingSessions.count, 1)
    }

    func testPraiseIsGrammatical() {
        for n in 0..<4 {
            let line = FormArea.legs.praise(n)
            XCTAssertNil(line.range(of: "that legs"), line)
            XCTAssertNil(line.range(of: "the legs"), line)
        }
    }

    func testCleanShooterGetsNoFocus() {
        let plan = CoachPlan(sessions: [session(Array(repeating: shot(), count: 40))])
        XCTAssertNil(plan.focus)
        XCTAssertEqual(plan.workout(hasBall: true).map(\.id), ["drill-formShooting", "maintain"])
    }

    func testFocusSticksUntilItGraduates() {
        // Guide hand was the focus; now the elbow is worse but guide hand isn't solid yet.
        let earlier = session(Array(repeating: shot([.guideHand: .needsWork]), count: 12), daysAgo: 2)
        let focusSet = session(Array(repeating: shot([.guideHand: .needsWork, .elbow: .needsWork]), count: 10), focus: .guideHand, daysAgo: 1)
        XCTAssertEqual(CoachPlan(sessions: [earlier, focusSet]).focus, .guideHand)
    }

    func testGraduatedFocusMovesOn() {
        let first = session(Array(repeating: shot([.guideHand: .needsWork, .elbow: .needsWork]), count: 10), focus: .guideHand, daysAgo: 3)
        let fixed = session(Array(repeating: shot([.elbow: .needsWork]), count: 30), focus: .guideHand, daysAgo: 1)
        let plan = CoachPlan(sessions: [first, fixed])
        XCTAssertGreaterThanOrEqual(plan.progress(for: .guideHand)!.stage, .solid)
        XCTAssertEqual(plan.graduated, [.guideHand])
        XCTAssertEqual(plan.focus, .elbow)
    }

    func testStages() {
        func stage(good: Int, of n: Int) -> AreaProgress.Stage {
            let shots = (0..<n).map { shot($0 < good ? [:] : [.elbow: .needsWork]) }
            return CoachPlan(sessions: [session(shots)]).progress(for: .elbow)!.stage
        }
        XCTAssertEqual(stage(good: 3, of: 4), .unmeasured)
        XCTAssertEqual(stage(good: 2, of: 10), .learning)
        XCTAssertEqual(stage(good: 5, of: 10), .building)
        XCTAssertEqual(stage(good: 9, of: 10), .building, "Needs 15 shots to be solid")
        XCTAssertEqual(stage(good: 12, of: 16), .solid)
        XCTAssertEqual(stage(good: 28, of: 30), .lockedIn)
        XCTAssertEqual(CoachPlan(sessions: []).progress(for: .arc)?.stage, .unmeasured)
    }

    func testTrendComparesWithPreviousWindow() {
        let old = (0..<30).map { shot($0 < 9 ? [:] : [.elbow: .needsWork]) }   // 30% good
        let new = (0..<30).map { shot($0 < 21 ? [:] : [.elbow: .needsWork]) }  // 70% good
        let p = CoachPlan(sessions: [session(old, daysAgo: 2), session(new)]).progress(for: .elbow)!
        XCTAssertEqual(p.measured, 30)
        XCTAssertEqual(p.trend, 40)
    }

    func testWorkoutWithoutBallUsesBallFreeDrills() {
        let plan = CoachPlan(sessions: [session(Array(repeating: shot([.elbow: .needsWork]), count: 15))])
        XCTAssertEqual(plan.focus, .elbow)
        let steps = plan.workout(hasBall: false)
        XCTAssertEqual(steps.first?.id, "warmup")
        XCTAssertEqual(steps.last?.id, "focus-elbow")
        for step in steps {
            if case .drill(let d) = step.kind { XCTAssertFalse(d.needsBall, d.id) }
        }
        XCTAssertTrue(steps.contains { if case .lesson(let l) = $0.kind { return l.area == .elbow }; return false })
    }

    func testWorkoutWithBallWarmsUpWithFormShooting() {
        let plan = CoachPlan(sessions: [session(Array(repeating: shot([.elbow: .needsWork]), count: 15))])
        guard case .drill(let warmUp) = plan.workout(hasBall: true).first?.kind else { return XCTFail() }
        XCTAssertEqual(warmUp.id, "formShooting")
    }

    func testGoalIsABitBetterThanNow() {
        let shots = (0..<20).map { shot($0 < 6 ? [:] : [.elbow: .needsWork]) }  // 30% good
        let plan = CoachPlan(sessions: [session(shots)])
        XCTAssertEqual(plan.goalRate(for: .elbow), 0.5, accuracy: 0.001)
        let better = CoachPlan(sessions: [session((0..<20).map { shot($0 < 13 ? [:] : [.elbow: .needsWork]) })])  // 65%
        XCTAssertEqual(better.goalRate(for: .elbow), 0.75, accuracy: 0.001)
        XCTAssertLessThanOrEqual(CoachPlan(sessions: [session(Array(repeating: shot(), count: 30))]).goalRate(for: .elbow), 0.9)
    }

    func testFocusSummary() {
        let shots = [shot(), shot([.elbow: .needsWork]), shot(areas: [.legs])]
        let r = SessionSummary(shots: shots, focus: .elbow).focusResult
        XCTAssertEqual(r?.good, 1)
        XCTAssertEqual(r?.measured, 2)
        XCTAssertNil(SessionSummary(shots: shots).focusResult)
    }

    func testChecklistIsPerDay() {
        let defaults = UserDefaults(suiteName: "CoachPlanTests")!
        defaults.removePersistentDomain(forName: "CoachPlanTests")
        let today = Date()
        let yesterday = today.addingTimeInterval(-86_400)
        WorkoutChecklist.set("warmup", done: true, on: today, defaults: defaults)
        XCTAssertEqual(WorkoutChecklist.done(on: today, defaults: defaults), ["warmup"])
        XCTAssertTrue(WorkoutChecklist.done(on: yesterday, defaults: defaults).isEmpty)
        WorkoutChecklist.set("warmup", done: false, on: today, defaults: defaults)
        XCTAssertTrue(WorkoutChecklist.done(on: today, defaults: defaults).isEmpty)
    }

    func testCurriculumIsComplete() {
        XCTAssertEqual(Set(Lesson.all.compactMap(\.area)), Set(FormArea.allCases))
        XCTAssertEqual(Set(Lesson.all.map(\.id)).count, Lesson.all.count)
        XCTAssertEqual(Set(Drill.all.map(\.id)).count, Drill.all.count)
        for lesson in Lesson.all {
            XCTAssertEqual(lesson.drills.count, lesson.drillIDs.count, "\(lesson.id) names a missing drill")
            if lesson.area != nil {
                XCTAssertTrue(lesson.drills.contains { !$0.needsBall }, "\(lesson.id) needs a no-ball drill")
                XCTAssertNotNil(lesson.howBuskChecks)
            }
        }
    }

    func testImprovedNeedsLowerSeverityOrBetterGrade() {
        func r(_ g: Grade, _ sev: Double) -> ShotResult {
            ShotResult(metrics: metrics, areas: [AreaResult(area: .elbow, grade: g, value: 0, detail: "", severity: sev)],
                       score: 0, cue: "Elbow in", focus: .elbow)
        }
        XCTAssertTrue(CoachSession.improved(.elbow, from: r(.needsWork, 1), to: r(.ok, 0)))
        XCTAssertTrue(CoachSession.improved(.elbow, from: r(.needsWork, 1), to: r(.needsWork, 0.5)))
        XCTAssertFalse(CoachSession.improved(.elbow, from: r(.needsWork, 1), to: r(.needsWork, 0.9)))
        XCTAssertFalse(CoachSession.improved(.elbow, from: r(.ok, 0), to: r(.needsWork, 1)))
        XCTAssertFalse(CoachSession.improved(.elbow, from: nil, to: r(.needsWork, 1)))
    }

    func testPlainDetailsHaveNoUnits() {
        for area in FormArea.allCases {
            for grade in [Grade.good, .ok, .needsWork] {
                let text = AreaResult(area: area, grade: grade, value: 0.12, detail: "").plain
                XCTAssertFalse(text.isEmpty)
                XCTAssertNil(text.range(of: #"[0-9%°]"#, options: .regularExpression), text)
            }
        }
    }
}
