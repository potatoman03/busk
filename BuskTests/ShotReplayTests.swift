import XCTest
@testable import Busk

final class ShotReplayTests: XCTestCase {
    private func clip(offset: CGFloat, size: CGFloat = 1, release: TimeInterval) -> ShotClip {
        let frames = (0..<60).map { i -> PoseFrame in
            let t = Double(i) / 30
            let lift = CGFloat(i) * 0.002
            let joints: [Joint: CGPoint] = [
                .leftShoulder: CGPoint(x: 0.45, y: 0.4), .rightShoulder: CGPoint(x: 0.55, y: 0.4),
                .leftHip: CGPoint(x: 0.46, y: 0.6), .rightHip: CGPoint(x: 0.54, y: 0.6),
                .rightWrist: CGPoint(x: 0.6, y: 0.3 - lift),
            ].mapValues { CGPoint(x: offset + $0.x * size, y: $0.y * size) }
            return PoseFrame(timestamp: 10 + t, joints: joints)
        }
        return ShotClip(frames: frames, release: 10 + release)
    }

    func testGhostIsLinedUpWithTheShotAtRelease() throws {
        let shot = clip(offset: 0, release: 1.0)
        let best = clip(offset: 0.3, size: 1.2, release: 0.8)
        let replay = ShotReplay(shot: shot, number: 3, score: 70, best: (best, 1, 90))
        let ghost = try XCTUnwrap(replay.ghost)
        let a = replay.shot.pose(at: 0), b = ghost.pose(at: 0)
        for joint in [Joint.leftHip, .rightHip, .leftShoulder, .rightShoulder] {
            let p = try XCTUnwrap(a[joint]), q = try XCTUnwrap(b[joint])
            XCTAssertEqual(p.x, q.x, accuracy: 0.002, "\(joint)")
            XCTAssertEqual(p.y, q.y, accuracy: 0.002, "\(joint)")
        }
        XCTAssertFalse(replay.isNewBest)
        XCTAssertEqual(ghost.number, 1)
    }

    func testReplayCoversTheReleaseWindow() {
        let replay = ShotReplay(shot: clip(offset: 0, release: 1.2), number: 1, score: 80, best: nil)
        XCTAssertNil(replay.ghost)
        XCTAssertTrue(replay.isNewBest)
        XCTAssertLessThanOrEqual(replay.shot.times.first!, -ShotReplay.before)
        XCTAssertGreaterThanOrEqual(replay.shot.times.last!, 0.6)
        XCTAssertEqual(replay.shot.pose(at: -5), replay.shot.poses.first)
    }

    @MainActor
    func testSessionReplaysEachShotAgainstTheBestOneOnlyWhenEnabled() {
        for enabled in [false, true] {
            let session = CoachSession(cameraView: .side, handedness: .right, source: DemoPoseSource(), voiceEnabled: false,
                                       ghostReplayEnabled: enabled)
            var sim = ShotSimulator()
            sim.view = .side
            var clock = 0.0
            var replays: [ShotReplay] = []
            for style in [ShotSimulator.Style.good, .noFollowThrough] {
                let shot = sim.idleFrames(seconds: 0.5, start: clock) + sim.frames(for: style, start: clock + 0.5)
                let frames = shot + sim.idleFrames(seconds: 1.5, start: shot.last!.timestamp + 1 / sim.fps)
                for f in frames {
                    session.handle(f)
                    if let r = session.replay, replays.last?.id != r.id { replays.append(r) }
                }
                clock = frames.last!.timestamp + 1 / sim.fps
            }
            XCTAssertEqual(session.shots.count, 2)
            if enabled {
                XCTAssertEqual(replays.count, 2)
                XCTAssertNil(replays[0].ghost)
                XCTAssertEqual(replays[1].ghost?.number, 1)
                XCTAssertEqual(replays[1].ghost?.score, session.shots[0].score)
            } else {
                XCTAssertTrue(replays.isEmpty)
            }
        }
    }
}
