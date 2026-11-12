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
            + Array(repeating: shot([.guideHand: .needsWork]), count: 4)
        XCTAssertEqual(CoachPlan(sessions: [session(shots)]).focus, .elbow)
    }

    func testTiesGoToEarlierInCurriculum() {
        let shots = Array(repeating: shot([.elbow: .needsWork, .legs: .needsWork]), count: 12)
        XCTAssertEqual(CoachPlan(sessions: [session(shots)]).focus, .legs)
    }

    func testCleanShooterGetsNoFocus() {
        XCTAssertNil(CoachPlan(sessions: [session(Array(repeating: shot(), count: 40))]).focus)
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
        let plan = CoachPlan(sessions: [session(Array(repeating: shot([.elbow: .needsWork]), count: 12))])
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
        let plan = CoachPlan(sessions: [session(Array(repeating: shot([.elbow: .needsWork]), count: 12))])
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
