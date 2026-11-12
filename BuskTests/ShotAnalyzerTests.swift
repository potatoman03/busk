import XCTest
@testable import Busk

final class ShotAnalyzerTests: XCTestCase {
    private func run(_ style: ShotSimulator.Style, handedness: Handedness = .right, view: CameraView = .side) -> [ShotMetrics] {
        var sim = ShotSimulator()
        sim.handedness = handedness
        sim.view = view
        let analyzer = ShotAnalyzer(handedness: handedness, view: view)
        let shot = sim.frames(for: style, start: 0.5)
        let frames = sim.idleFrames(seconds: 0.5, start: 0) + shot + sim.idleFrames(seconds: 1.5, start: shot.last!.timestamp + 1 / sim.fps)
        return frames.compactMap { analyzer.process($0) }
    }

    func testDetectsExactlyOneShotPerSequence() {
        for view in CameraView.allCases {
            for style in ShotSimulator.Style.demoRotation(for: view) {
                XCTAssertEqual(run(style, view: view).count, 1, "\(view) \(style.name)")
            }
        }
    }

    func testLowFrameRateSkipsTimingChecks() throws {
        // 15 frames a second (Vision or the camera falling behind): too few frames to see a short hold, so the set point,
        // hitch and release timing aren't judged; the rest still is.
        var sim = ShotSimulator()
        sim.fps = 15
        let analyzer = ShotAnalyzer(handedness: .right, view: .side)
        let shot = sim.frames(for: .good, start: 0.5)
        let frames = sim.idleFrames(seconds: 0.5, start: 0) + shot + sim.idleFrames(seconds: 1.5, start: shot.last!.timestamp + 1 / sim.fps)
        let m = try XCTUnwrap(frames.compactMap { analyzer.process($0) }.first)
        XCTAssertNil(m.setPointHeight)
        XCTAssertNil(m.hitch)
        XCTAssertNil(m.releaseTiming)
        XCTAssertNotNil(m.armAngle)
        XCTAssertEqual(FormEvaluator().evaluate(m).cue, FormEvaluator().evaluate(try XCTUnwrap(run(.good).first)).cue)
    }

    func testReleaseRightAfterDroppedFramesDoesNotCrash() {
        // Vision losing the shooter through the whole gather leaves no frames before the release to measure.
        let sim = ShotSimulator()
        let shot = sim.frames(for: .good, start: 0)
        for cut in stride(from: 0.5, to: 1.3, by: 0.033) {
            let analyzer = ShotAnalyzer(handedness: .right, view: .front)
            let frames = shot.filter { $0.timestamp < 0.3 || $0.timestamp >= cut }
                + sim.idleFrames(seconds: 1.5, start: shot.last!.timestamp + 1 / sim.fps)
            _ = frames.compactMap { analyzer.process($0) }
        }
    }

    func testIdleFramesProduceNoShots() {
        let analyzer = ShotAnalyzer(handedness: .right, view: .side)
        let shots = ShotSimulator().idleFrames(seconds: 5, start: 0).compactMap { analyzer.process($0) }
        XCTAssertTrue(shots.isEmpty)
    }

    func testGoodFormMetrics() throws {
        let m = try XCTUnwrap(run(.good).first)
        XCTAssertGreaterThan(try XCTUnwrap(m.setPointHeight), 0.1)
        XCTAssertGreaterThan(try XCTUnwrap(m.armAngle), 65)
        XCTAssertGreaterThan(m.followThrough, 0.6)
        XCTAssertGreaterThan(try XCTUnwrap(m.legDrive), 0.03)
        XCTAssertLessThan(abs(try XCTUnwrap(m.releaseTiming)), 0.5)
        XCTAssertLessThan(try XCTUnwrap(m.drift), 0.05)
        XCTAssertLessThan(try XCTUnwrap(m.hitch), 0.1)
        XCTAssertNil(m.elbowFlare)
    }

    func testChestPushHasLowSetPoint() throws {
        XCTAssertLessThan(try XCTUnwrap(run(.lowSet).first?.setPointHeight), 0)
    }

    func testFlatShotHasLowArmAngle() throws {
        XCTAssertLessThan(try XCTUnwrap(run(.flat).first?.armAngle), 60)
    }

    func testHitchIsTimed() throws {
        XCTAssertGreaterThan(try XCTUnwrap(run(.hitched).first?.hitch), FormEvaluator.Thresholds().hitch.bad)
        XCTAssertLessThan(try XCTUnwrap(run(.good).first?.hitch), FormEvaluator.Thresholds().hitch.ok)
    }

    func testFaderDrifts() throws {
        let m = try XCTUnwrap(run(.fader).first)
        XCTAssertLessThan(try XCTUnwrap(m.releaseTiming), 0.2)
        XCTAssertGreaterThan(try XCTUnwrap(m.drift), 0.16)
    }

    func testLateRelease() throws {
        let m = try XCTUnwrap(run(.lateRelease).first)
        XCTAssertGreaterThan(try XCTUnwrap(m.releaseTiming), 0.33)
        XCTAssertLessThan(try XCTUnwrap(m.drift), 0.11)
    }

    func testShortFollowThrough() throws {
        XCTAssertLessThan(try XCTUnwrap(run(.noFollowThrough).first).followThrough, 0.25)
    }

    func testFrontViewMeasuresElbowAndGuideHand() throws {
        let good = try XCTUnwrap(run(.good, view: .front).first)
        XCTAssertNil(good.armAngle)
        XCTAssertLessThan(try XCTUnwrap(good.elbowFlare), 0.05)
        XCTAssertLessThan(try XCTUnwrap(good.guideHandPush), 0.025)
        XCTAssertGreaterThan(try XCTUnwrap(run(.flaredElbow, view: .front).first?.elbowFlare), 0.07)
        XCTAssertGreaterThan(try XCTUnwrap(run(.guideThumb, view: .front).first?.guideHandPush), 0.035)
    }

    func testLeftHandedShot() throws {
        let m = try XCTUnwrap(run(.good, handedness: .left).first)
        XCTAssertGreaterThan(try XCTUnwrap(m.armAngle), 65)
        XCTAssertGreaterThan(try XCTUnwrap(m.setPointHeight), 0.1)
    }

    func testUnknownViewSkipsAngleSpecificChecks() throws {
        var sim = ShotSimulator()
        sim.view = .front
        let analyzer = ShotAnalyzer(handedness: .right, view: nil)
        let shot = sim.frames(for: .good, start: 0)
        let m = try XCTUnwrap((shot + sim.idleFrames(seconds: 1.5, start: shot.last!.timestamp + 0.04)).compactMap { analyzer.process($0) }.first)
        XCTAssertNil(m.armAngle)
        XCTAssertNil(m.elbowFlare)
        XCTAssertNil(m.guideHandPush)
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

    func testFramesFromSomeoneElseBeforeTheTrackerLocksOnAreNotMeasured() throws {
        // At a crowded court the tracker can follow a bystander (arms down) until the shooter starts the shot.
        let sim = ShotSimulator()
        let shot = sim.frames(for: .good, start: 0)
        let bystander = sim.idleFrames(seconds: 0.7, start: 0).map { f -> PoseFrame in
            var f = f
            f.joints = f.joints.mapValues { CGPoint(x: $0.x - 0.35, y: $0.y) }
            return f
        }
        let frames = bystander + shot.filter { $0.timestamp >= 0.7 }
            + sim.idleFrames(seconds: 1.5, start: shot.last!.timestamp + 1 / sim.fps)
        let analyzer = ShotAnalyzer(handedness: .right, view: .side)
        let m = try XCTUnwrap(frames.compactMap { analyzer.process($0) }.first)
        XCTAssertNotEqual(FormEvaluator().evaluate(m).cue, FormEvaluator().evaluate(try XCTUnwrap(run(.lowSet).first)).cue)
        if let set = m.setPointHeight { XCTAssertGreaterThan(set, 0) }
    }

    func testLoopedClipMeasuresTheSameEachTime() {
        let sim = ShotSimulator()
        let analyzer = ShotAnalyzer(handedness: .right, view: .front)
        let shot = sim.frames(for: .good, start: 0)
        let still = Array(repeating: shot.last!, count: 45)
        var frames: [PoseFrame] = []
        var offset = 0.0
        for _ in 0..<3 {
            for (i, f) in (shot + still).enumerated() { var f = f; f.timestamp = offset + Double(i) / sim.fps; frames.append(f) }
            offset = frames.last!.timestamp + 1
        }
        let shots = frames.compactMap { analyzer.process($0) }
        XCTAssertEqual(shots.count, 3)
        XCTAssertEqual(Set(shots.map { $0.elbowFlare }).count, 1)
        XCTAssertEqual(Set(shots.map { $0.setPointHeight }).count, 1)
    }

    func testConsecutiveShots() {
        let sim = ShotSimulator()
        let analyzer = ShotAnalyzer(handedness: .right, view: .side)
        let styles = ShotSimulator.Style.demoRotation(for: .side)
        var frames: [PoseFrame] = []
        var t = 0.0
        for style in styles {
            let shot = sim.frames(for: style, start: t) + sim.idleFrames(seconds: 0.8, start: 0)
            for f in shot { var f = f; f.timestamp = t; frames.append(f); t += 1 / sim.fps }
        }
        XCTAssertEqual(frames.compactMap { analyzer.process($0) }.count, styles.count)
    }
}
