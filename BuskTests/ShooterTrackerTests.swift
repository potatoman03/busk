import CoreGraphics
import XCTest
@testable import Busk

final class ShooterTrackerTests: XCTestCase {
    /// A standing person centred at `x`, `height` tall with feet at `floor`, optionally with the right hand up.
    private func person(x: CGFloat, height: CGFloat, floor: CGFloat = 0.9, handUp: Bool = false) -> [Joint: CGPoint] {
        let top = floor - height
        let shoulder = top + height * 0.18
        return [
            .nose: CGPoint(x: x, y: top + height * 0.05), .neck: CGPoint(x: x, y: shoulder),
            .leftShoulder: CGPoint(x: x - height * 0.1, y: shoulder), .rightShoulder: CGPoint(x: x + height * 0.1, y: shoulder),
            .leftWrist: CGPoint(x: x - height * 0.1, y: top + height * 0.5),
            .rightWrist: CGPoint(x: x + height * 0.1, y: handUp ? top - height * 0.1 : top + height * 0.5),
            .leftHip: CGPoint(x: x - height * 0.07, y: top + height * 0.5), .rightHip: CGPoint(x: x + height * 0.07, y: top + height * 0.5),
            .leftAnkle: CGPoint(x: x - height * 0.07, y: floor), .rightAnkle: CGPoint(x: x + height * 0.07, y: floor),
        ]
    }

    func testSwitchesFromBiggerBystanderToShooterRaisingTheBall() {
        let tracker = ShooterTracker()
        let bystander = person(x: 0.3, height: 0.5, floor: 0.95)
        XCTAssertEqual(tracker.select([bystander, person(x: 0.6, height: 0.4, floor: 0.8)]), bystander)
        let shooting = person(x: 0.6, height: 0.4, floor: 0.8, handUp: true)
        XCTAssertEqual(tracker.select([bystander, shooting]), shooting)
        let landed = person(x: 0.61, height: 0.4, floor: 0.8)
        XCTAssertEqual(tracker.select([bystander, landed]), landed, "stays on the shooter once their hand comes down")
    }

    func testRewindKeepsTheShooterWhenALoopingClipRestarts() {
        let tracker = ShooterTracker()
        let bystander = person(x: 0.2, height: 0.45, floor: 0.95)
        let shot = person(x: 0.5, height: 0.4, handUp: true)
        XCTAssertEqual(tracker.select([bystander, shot]), shot)
        tracker.rewind()
        let start = person(x: 0.44, height: 0.4)
        XCTAssertEqual(tracker.select([bystander, start]), start, "back at the start spot, still the shooter")
    }

    func testIgnoresHandsUpInTheStands() {
        let tracker = ShooterTracker()
        let shooter = person(x: 0.5, height: 0.4, floor: 0.9)
        XCTAssertEqual(tracker.select([shooter]), shooter)
        let fan = person(x: 0.8, height: 0.3, floor: 0.35, handUp: true)
        XCTAssertEqual(tracker.select([shooter, fan]), shooter)
    }

    func testWaitsForTheShooterWhenTheyDropOutBriefly() {
        let tracker = ShooterTracker()
        let shooter = person(x: 0.5, height: 0.4)
        XCTAssertEqual(tracker.select([shooter]), shooter)
        XCTAssertNil(tracker.select([person(x: 0.2, height: 0.45)]), "doesn't jump to someone else for one missed frame")
        XCTAssertEqual(tracker.select([shooter]), shooter)
    }

    func testStaysOnTheShooterAfterTheShotWhenSomeoneElseRaisesAHand() {
        let tracker = ShooterTracker()
        let shooter = person(x: 0.5, height: 0.4, handUp: true)
        XCTAssertEqual(tracker.select([shooter]), shooter)
        let landed = person(x: 0.5, height: 0.4)
        let defender = person(x: 0.7, height: 0.42, handUp: true)
        for _ in 0..<30 { XCTAssertEqual(tracker.select([landed, defender]), landed) }
    }
}
