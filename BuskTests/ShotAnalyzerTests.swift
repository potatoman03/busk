import XCTest
@testable import Busk

final class ShotAnalyzerTests: XCTestCase {
    private func run(_ style: ShotSimulator.Style, handedness: Handedness = .right, view: CameraView = .side) -> [ShotMetrics] {
        var sim = ShotSimulator()
        sim.handedness = handedness
        let analyzer = ShotAnalyzer(handedness: handedness, view: view)
        let frames = sim.idleFrames(seconds: 0.5, start: 0) + sim.frames(for: style, start: 0.5)
        return frames.compactMap { analyzer.process($0) }
    }

    func testDetectsExactlyOneShotPerSequence() {
        for style in ShotSimulator.Style.demoRotation {
            XCTAssertEqual(run(style).count, 1, style.name)
        }
    }

    func testIdleFramesProduceNoShots() {
        let analyzer = ShotAnalyzer(handedness: .right, view: .side)
        let shots = ShotSimulator().idleFrames(seconds: 5, start: 0).compactMap { analyzer.process($0) }
        XCTAssertTrue(shots.isEmpty)
        XCTAssertEqual(analyzer.phase, .waiting)
    }

    func testGoodFormMeasuresWithinTargets() throws {
        let m = try XCTUnwrap(run(.good).first)
        XCTAssertLessThan(m.elbowOffset, 0.2)
        XCTAssertGreaterThan(m.releaseElbowAngle, 160)
        XCTAssertGreaterThan(m.releaseHeight, 0.45)
        XCTAssertEqual(try XCTUnwrap(m.releaseAngle), 68, accuracy: 10)
        XCTAssertGreaterThan(m.followThrough, 0.4)
        XCTAssertLessThan(try XCTUnwrap(m.kneeAngle), 150)
    }

    func testFlaredElbowIsMeasured() throws {
        let m = try XCTUnwrap(run(.flaredElbow).first)
        XCTAssertGreaterThan(m.elbowOffset, 0.5)
    }

    func testFlatShotHasLowReleaseAngle() throws {
        let m = try XCTUnwrap(run(.flat).first)
        XCTAssertLessThan(try XCTUnwrap(m.releaseAngle), 45)
    }

    func testShortFollowThrough() throws {
        let m = try XCTUnwrap(run(.noFollowThrough).first)
        XCTAssertLessThan(m.followThrough, 0.25)
    }

    func testLeftHandedShooter() throws {
        let m = try XCTUnwrap(run(.good, handedness: .left).first)
        XCTAssertGreaterThan(m.releaseElbowAngle, 160)
    }

    func testFrontViewSkipsArc() throws {
        let m = try XCTUnwrap(run(.good, view: .front).first)
        XCTAssertNil(m.releaseAngle)
    }

    func testMissingJointsAreIgnored() {
        let analyzer = ShotAnalyzer(handedness: .right, view: .side)
        let frames = ShotSimulator().frames(for: .good).map { f -> PoseFrame in
            var f = f
            f.joints[.rightWrist] = nil
            return f
        }
        XCTAssertTrue(frames.compactMap { analyzer.process($0) }.isEmpty)
    }

    func testConsecutiveShots() {
        let sim = ShotSimulator()
        let analyzer = ShotAnalyzer(handedness: .right, view: .side)
        var frames: [PoseFrame] = []
        var t = 0.0
        for style in ShotSimulator.Style.demoRotation {
            let shot = sim.frames(for: style, start: t)
            frames += shot
            t = (shot.last?.timestamp ?? t) + 1 / sim.fps
        }
        XCTAssertEqual(frames.compactMap { analyzer.process($0) }.count, ShotSimulator.Style.demoRotation.count)
    }
}
