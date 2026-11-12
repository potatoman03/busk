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
}
