import XCTest
@testable import Busk

final class FramingCheckTests: XCTestCase {
    private let full: [Joint: CGPoint] = [
        .nose: CGPoint(x: 0.5, y: 0.2), .rightShoulder: CGPoint(x: 0.45, y: 0.3), .rightElbow: CGPoint(x: 0.42, y: 0.4),
        .rightWrist: CGPoint(x: 0.42, y: 0.5), .leftHip: CGPoint(x: 0.52, y: 0.55), .rightHip: CGPoint(x: 0.48, y: 0.55),
        .leftAnkle: CGPoint(x: 0.52, y: 0.9), .rightAnkle: CGPoint(x: 0.48, y: 0.9),
    ]

    private func check(_ joints: [Joint: CGPoint]) -> FramingCheck {
        FramingCheck(frame: PoseFrame(timestamp: 0, joints: joints), handedness: .right)
    }

    func testWholeBodyIsGood() {
        XCTAssertTrue(check(full).isGood)
        XCTAssertNil(check(full).advice)
    }

    func testNobody() {
        XCTAssertEqual(check([:]).advice, "Step in front of the camera, 3 to 4 metres away")
    }

    func testFeetCutOff() {
        var j = full
        j[.leftAnkle] = nil
        j[.rightAnkle] = CGPoint(x: 0.48, y: 0.99)
        XCTAssertFalse(check(j).feet)
        XCTAssertTrue(check(j).advice!.contains("feet"))
    }

    func testTooCloseMissesHeadAndFeet() {
        var j = full
        j[.nose] = nil
        j[.leftAnkle] = nil
        j[.rightAnkle] = nil
        XCTAssertEqual(check(j).advice, "Step back. Busk needs you head to feet")
    }

    func testOffToTheSide() {
        var j = full
        j[.leftHip] = CGPoint(x: 0.95, y: 0.55)
        XCTAssertFalse(check(j).centred)
        XCTAssertEqual(check(j).advice, "Move to the middle of the picture")
    }

    func testShootingArmMissing() {
        var j = full
        j[.rightWrist] = nil
        XCTAssertTrue(check(j).advice!.contains("shooting arm"))
    }
}
