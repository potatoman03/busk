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
}
