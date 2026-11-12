import XCTest
@testable import Busk

final class FormEvaluatorTests: XCTestCase {
    private let good = ShotMetrics(setElbowAngle: 95, elbowOffset: 0.05, releaseElbowAngle: 172, releaseHeight: 0.55,
                                   releaseAngle: 68, followThrough: 0.6, kneeAngle: 140)

    func testGoodShotScoresHighAndPraises() {
        let r = FormEvaluator().evaluate(good)
        XCTAssertEqual(r.score, 100)
        XCTAssertNil(r.focus)
        XCTAssertEqual(r.cue, "Great shot, same again")
        XCTAssertTrue(r.areas.allSatisfy { $0.grade == .good })
    }

    func testElbowFaultTakesPriority() {
        var m = good
        m.elbowOffset = 0.8
        m.followThrough = 0.05
        let r = FormEvaluator().evaluate(m)
        XCTAssertEqual(r.focus, .elbow)
        XCTAssertEqual(r.cue, FormArea.elbow.cue)
        XCTAssertEqual(r.score, 60)
    }

    func testFlatArcCue() {
        var m = good
        m.releaseAngle = 35
        XCTAssertEqual(FormEvaluator().evaluate(m).cue, FormArea.arc.cue)
    }

    func testFollowThroughCue() {
        var m = good
        m.followThrough = 0.1
        XCTAssertEqual(FormEvaluator().evaluate(m).focus, .followThrough)
    }

    func testMinorIssueGetsSoftCue() {
        var m = good
        m.releaseElbowAngle = 155
        let r = FormEvaluator().evaluate(m)
        XCTAssertEqual(r.score, 93)
        XCTAssertEqual(r.focus, .armExtension)
        XCTAssertEqual(r.cue, "Great shot, same again")
    }

    func testOptionalAreasOmitted() {
        var m = good
        m.releaseAngle = nil
        m.kneeAngle = nil
        let areas = FormEvaluator().evaluate(m).areas.map(\.area)
        XCTAssertFalse(areas.contains(.arc))
        XCTAssertFalse(areas.contains(.legs))
    }

    func testSimulatedStylesGetExpectedFocus() {
        let expected: [(ShotSimulator.Style, FormArea?)] = [
            (.good, nil), (.flaredElbow, .elbow), (.flat, .arc), (.noFollowThrough, .followThrough), (.stiffLegs, .legs),
        ]
        for (style, focus) in expected {
            let analyzer = ShotAnalyzer(handedness: .right, view: .side)
            let metrics = ShotSimulator().frames(for: style).compactMap { analyzer.process($0) }.first
            XCTAssertNotNil(metrics, style.name)
            let r = metrics.map { FormEvaluator().evaluate($0) }
            XCTAssertEqual(r?.focus, focus, "\(style.name): \(String(describing: r?.areas))")
        }
    }

    func testSessionSummary() {
        let e = FormEvaluator()
        var bad = good
        bad.elbowOffset = 0.9
        let s = SessionSummary(shots: [e.evaluate(good), e.evaluate(bad), e.evaluate(bad)])
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s.bestScore, 100)
        XCTAssertEqual(s.averageScore, 87)
        XCTAssertEqual(s.topFocus, .elbow)
    }
}
