import XCTest
@testable import Busk

final class ReplayPoseSourceTests: XCTestCase {
    func testParsesBenchmarkKeypoints() throws {
        let json = """
        {"format":"busk-bench-keypoints/1","fps":30,"width":720,"height":1280,"view":"front","handedness":"left",
         "frames":[{"t":0,"joints":{"left_shoulder":[0.4,0.3],"right_wrist":[0.6,0.5],"ball":[0,0]}}]}
        """
        let clip = try ReplayPoseSource.parse(Data(json.utf8))
        XCTAssertEqual(clip.view, .front)
        XCTAssertEqual(clip.handedness, .left)
        XCTAssertEqual(clip.aspectRatio, 0.5625, accuracy: 1e-6)
        XCTAssertEqual(clip.frames.count, 1)
        XCTAssertEqual(clip.frames[0][.leftShoulder], CGPoint(x: 0.4, y: 0.3))
        XCTAssertEqual(clip.frames[0][.rightWrist], CGPoint(x: 0.6, y: 0.5))
        XCTAssertEqual(clip.frames[0].count, 2)
    }

    func testRejectsEmptyClip() {
        XCTAssertThrowsError(try ReplayPoseSource.parse(Data(#"{"frames":[]}"#.utf8)))
    }

    func testWideClipOverlayCentresOnShooter() {
        let size = CGSize(width: 400, height: 800)
        let map = SkeletonOverlay.mapper(size: size, aspectRatio: 16.0 / 9.0, centerX: 0.34)
        XCTAssertEqual(map(CGPoint(x: 0.34, y: 0.5)).x, 200, accuracy: 1e-6)
        let edge = SkeletonOverlay.mapper(size: size, aspectRatio: 16.0 / 9.0, centerX: 0.0)
        XCTAssertEqual(edge(CGPoint(x: 0, y: 0.5)).x, 0, accuracy: 1e-6)
        let centred = SkeletonOverlay.mapper(size: size, aspectRatio: 16.0 / 9.0)
        XCTAssertEqual(centred(CGPoint(x: 0.5, y: 0.5)).x, 200, accuracy: 1e-6)
    }

    func testPortraitPoseFitsLandscapeScreen() {
        let size = CGSize(width: 844, height: 390)
        let map = SkeletonOverlay.mapper(size: size, aspectRatio: 9.0 / 16.0, fill: false)
        let head = map(CGPoint(x: 0.5, y: 0.05)), feet = map(CGPoint(x: 0.5, y: 0.95))
        XCTAssertGreaterThanOrEqual(head.y, 0)
        XCTAssertLessThanOrEqual(feet.y, size.height)
        XCTAssertEqual(head.x, size.width / 2, accuracy: 1e-6)
    }

    func testVideoOrientationFromTrackTransform() {
        XCTAssertEqual(VideoPoseSource.orientation(for: .identity), .up)
        XCTAssertEqual(VideoPoseSource.orientation(for: CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 0, ty: 0)), .right)
    }

    func testReplayReportsEveryFramePlayed() {
        let frames = Array(repeating: [Joint.nose: CGPoint(x: 0.5, y: 0.1)], count: 6)
        let source = ReplayPoseSource(clip: .init(fps: 60, view: .side, handedness: .right, aspectRatio: 1, frames: frames))
        var delivered = 0
        source.onFrame = { _ in delivered += 1 }
        let done = expectation(description: "finished")
        source.onFinished = { done.fulfill() }
        source.start()
        wait(for: [done], timeout: 5)
        XCTAssertEqual(source.framesPlayed, 6)
        XCTAssertEqual(delivered, 6 + 90)
    }

    func testReplayStatusRoundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "replay-status-test.json")
        let status = ReplayStatus(label: "clip", path: "/x.json", frames: 10, framesPlayed: 10, shots: 1, cues: ["Hold it"], finished: true)
        status.write(to: url)
        XCTAssertEqual(try JSONDecoder().decode(ReplayStatus.self, from: Data(contentsOf: url)), status)
    }

    func testVideoKeepsDrawingWhenLiveVisionKeepsPlaybackBehind() {
        XCTAssertTrue(VideoPoseSource.shouldDraw(at: 0, behind: true, lastDrawn: nil))
        XCTAssertTrue(VideoPoseSource.shouldDraw(at: 0.05, behind: false, lastDrawn: 0))
        XCTAssertFalse(VideoPoseSource.shouldDraw(at: 0.1, behind: true, lastDrawn: 0))
        XCTAssertTrue(VideoPoseSource.shouldDraw(at: 0.2, behind: true, lastDrawn: 0))
    }
}
