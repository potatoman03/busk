import XCTest
@testable import Busk

final class FormEvaluatorTests: XCTestCase {
    private let good = ShotMetrics(view: .front, setPointHeight: 0.15, elbowFlare: 0.02, armAngle: nil, followThrough: 0.8,
                                   legDrive: 0.04, releaseTiming: 0, hitch: 0, drift: 0.02, guideHandPush: 0.01)

    func testGoodShot() {
        let r = FormEvaluator().evaluate(good)
        XCTAssertEqual(r.score, 100)
        XCTAssertNil(r.focus)
        XCTAssertTrue(r.fixes.isEmpty)
        XCTAssertEqual(r.cue, "Great shot, same again")
    }

    func testEveryFlawIsFlagged() {
        let cases: [(FormArea, (inout ShotMetrics) -> Void)] = [
            (.setPoint, { $0.setPointHeight = -0.05 }),
            (.releaseTiming, { $0.releaseTiming = 0.6 }),
            (.balance, { $0.drift = 0.25 }),
            (.rhythm, { $0.hitch = 0.3 }),
            (.elbow, { $0.elbowFlare = 0.1 }),
            (.guideHand, { $0.guideHandPush = 0.08 }),
            (.legs, { $0.legDrive = 0.005 }),
            (.followThrough, { $0.followThrough = 0.1 }),
        ]
        for (area, change) in cases {
            var m = good
            change(&m)
            let r = FormEvaluator().evaluate(m)
            XCTAssertEqual(r.fixes, [area], area.rawValue)
            XCTAssertEqual(r.cue, area.cue)
            XCTAssertEqual(r.score, 80)
        }
        var side = good
        side.view = .side
        side.elbowFlare = nil
        side.guideHandPush = nil
        side.armAngle = 40
        XCTAssertEqual(FormEvaluator().evaluate(side).fixes, [.arc])
    }

    func testWorstFlawComesFirst() {
        var m = good
        m.followThrough = 0.2   // just past the line
        m.setPointHeight = -0.2 // far past it
        let r = FormEvaluator().evaluate(m)
        XCTAssertEqual(r.fixes, [.setPoint, .followThrough])
        XCTAssertEqual(r.focus, .setPoint)
        XCTAssertEqual(r.score, 60)
    }

    func testMinorIssueIsNotCorrected() {
        var m = good
        m.followThrough = 0.3
        let r = FormEvaluator().evaluate(m)
        XCTAssertEqual(r.score, 93)
        XCTAssertNil(r.focus)
        XCTAssertEqual(r.cue, "Great shot, same again")
    }

    func testCleanShotIsNotToldToBendKnees() {
        XCTAssertFalse(FormEvaluator().evaluate(good).fixes.contains(.legs))
    }

    func testUnmeasuredAreasAreOmitted() {
        var m = good
        m.elbowFlare = nil
        m.legDrive = nil
        m.releaseTiming = nil
        let areas = FormEvaluator().evaluate(m).areas.map(\.area)
        XCTAssertFalse(areas.contains(.elbow))
        XCTAssertFalse(areas.contains(.legs))
        XCTAssertFalse(areas.contains(.arc))
        XCTAssertFalse(areas.contains(.releaseTiming))
    }

    func testSimulatedStylesGetExpectedFocus() {
        let expected: [(CameraView, ShotSimulator.Style, FormArea?)] = [
            (.side, .good, nil), (.side, .lowSet, .setPoint), (.side, .flat, .arc), (.side, .hitched, .rhythm),
            (.side, .noFollowThrough, .followThrough), (.side, .stiffLegs, .legs),
            (.front, .good, nil), (.front, .flaredElbow, .elbow), (.front, .guideThumb, .guideHand),
        ]
        for (view, style, focus) in expected {
            var sim = ShotSimulator()
            sim.view = view
            let analyzer = ShotAnalyzer(handedness: .right, view: view)
            let shot = sim.frames(for: style)
            let metrics = (shot + sim.idleFrames(seconds: 1.5, start: shot.last!.timestamp + 0.04)).compactMap { analyzer.process($0) }.first
            XCTAssertNotNil(metrics, style.name)
            let r = metrics.map { FormEvaluator().evaluate($0) }
            XCTAssertEqual(r?.focus, focus, "\(view) \(style.name): \(String(describing: r?.areas))")
        }
        var sim = ShotSimulator()
        sim.view = .side
        let analyzer = ShotAnalyzer(handedness: .right, view: .side)
        let shot = sim.frames(for: .fader)
        let fader = (shot + sim.idleFrames(seconds: 1.5, start: shot.last!.timestamp + 0.04)).compactMap { analyzer.process($0) }.first
        XCTAssertEqual(Set(fader.map { FormEvaluator().evaluate($0).fixes } ?? []), [.releaseTiming, .balance])
    }

    func testSessionSummary() {
        let e = FormEvaluator()
        var bad = good
        bad.elbowFlare = 0.12
        let s = SessionSummary(shots: [e.evaluate(good), e.evaluate(bad), e.evaluate(bad)])
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.bestScore, 100)
        XCTAssertEqual(s.averageScore, 87)
        XCTAssertEqual(s.topFocus, .elbow)
    }
}
