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

    func testIdleFramesProduceNoShots() {
        let analyzer = ShotAnalyzer(handedness: .right, view: .side)
        let shots = ShotSimulator().idleFrames(seconds: 5, start: 0).compactMap { analyzer.process($0) }
        XCTAssertTrue(shots.isEmpty)
    }

    func testGoodFormMetrics() throws {
        let m = try XCTUnwrap(run(.good).first)
        XCTAssertGreaterThan(m.setPointHeight, 0.1)
        XCTAssertGreaterThan(try XCTUnwrap(m.armAngle), 65)
        XCTAssertGreaterThan(m.followThrough, 0.6)
        XCTAssertGreaterThan(try XCTUnwrap(m.legDrive), 0.03)
        XCTAssertLessThan(abs(try XCTUnwrap(m.releaseTiming)), 0.5)
        XCTAssertLessThan(try XCTUnwrap(m.drift), 0.05)
        XCTAssertLessThan(m.hitch, 0.1)
        XCTAssertNil(m.elbowFlare)
    }

    func testChestPushHasLowSetPoint() throws {
        XCTAssertLessThan(try XCTUnwrap(run(.lowSet).first).setPointHeight, 0)
    }

    func testFlatShotHasLowArmAngle() throws {
        XCTAssertLessThan(try XCTUnwrap(run(.flat).first?.armAngle), 60)
    }

    func testHitchIsTimed() throws {
        XCTAssertEqual(try XCTUnwrap(run(.hitched).first).hitch, 0.3, accuracy: 0.1)
    }

    func testFaderReleasesLateAndDrifts() throws {
        let m = try XCTUnwrap(run(.fader).first)
        XCTAssertGreaterThan(try XCTUnwrap(m.releaseTiming), 0.3)
        XCTAssertGreaterThan(try XCTUnwrap(m.drift), 0.16)
    }

    func testShortFollowThrough() throws {
        XCTAssertLessThan(try XCTUnwrap(run(.noFollowThrough).first).followThrough, 0.25)
    }

    func testFrontViewMeasuresElbowAndGuideHand() throws {
        let good = try XCTUnwrap(run(.good, view: .front).first)
        XCTAssertNil(good.armAngle)
        XCTAssertLessThan(try XCTUnwrap(good.elbowFlare), 0.05)
        XCTAssertLessThan(try XCTUnwrap(good.guideHandPush), 0.035)
        XCTAssertGreaterThan(try XCTUnwrap(run(.flaredElbow, view: .front).first?.elbowFlare), 0.07)
        XCTAssertGreaterThan(try XCTUnwrap(run(.guideThumb, view: .front).first?.guideHandPush), 0.05)
    }

    func testLeftHandedShot() throws {
        let m = try XCTUnwrap(run(.good, handedness: .left).first)
        XCTAssertGreaterThan(try XCTUnwrap(m.armAngle), 65)
        XCTAssertGreaterThan(m.setPointHeight, 0.1)
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
