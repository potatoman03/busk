import XCTest

final class BuskUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    /// Rotates and waits for the layout to settle, so screenshots aren't taken mid-rotation.
    private func rotate(_ orientation: UIDeviceOrientation) {
        XCUIDevice.shared.orientation = orientation
        let window = app.windows.firstMatch
        let wide = orientation.isLandscape
        for _ in 0..<20 where (window.frame.width > window.frame.height) != wide {
            Thread.sleep(forTimeInterval: 0.2)
        }
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func snapshot(_ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }

    func testHomeScreen() {
        XCTAssertTrue(app.navigationBars["Busk"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["startButton"].exists)
        XCTAssertTrue(app.buttons["settingsButton"].exists)
        XCTAssertTrue(app.buttons["historyButton"].exists)
        XCTAssertTrue(app.staticTexts["Elbow"].exists)
        snapshot("01-home")
    }

    func testFullShootingSession() {
        app.buttons["startButton"].tap()
        XCTAssertTrue(app.buttons["goLiveButton"].waitForExistence(timeout: 5))
        app.segmentedControls["cameraViewPicker"].buttons["Side on"].tap()
        snapshot("02-setup")
        app.buttons["goLiveButton"].tap()

        XCTAssertTrue(app.staticTexts["demoBadge"].waitForExistence(timeout: 5) || app.otherElements["demoBadge"].exists)
        let count = app.staticTexts["shotCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        let twoShots = NSPredicate(format: "label.integerValue >= 2")
        expectation(for: twoShots, evaluatedWith: count)
        waitForExpectations(timeout: 60)
        XCTAssertTrue(app.staticTexts["lastShotScore"].exists)
        XCTAssertTrue(app.staticTexts["cueBanner"].exists)
        let spoken = app.staticTexts["lastSpokenCue"]
        XCTAssertTrue(spoken.exists)
        // The demo keeps shooting, so a new cue can land between the two reads; retry until they line up.
        var matched = false
        for _ in 0..<10 where !matched {
            matched = spoken.label.contains(app.staticTexts["cueBanner"].label)
            if !matched { Thread.sleep(forTimeInterval: 0.3) }
        }
        XCTAssertTrue(matched, spoken.label)
        snapshot("03-live")

        rotate(.landscapeLeft)
        defer { XCUIDevice.shared.orientation = .portrait }
        let end = app.buttons["endSessionButton"]
        XCTAssertTrue(end.waitForExistence(timeout: 5))
        snapshot("03b-live-landscape")

        end.tap()
        XCTAssertTrue(app.staticTexts["summaryShotCount"].waitForExistence(timeout: 5))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertGreaterThanOrEqual(Int(app.staticTexts["summaryShotCount"].label) ?? 0, 2)
        snapshot("04-summary")
        app.buttons["summaryDoneButton"].tap()

        XCTAssertTrue(app.buttons["lastSessionCard"].waitForExistence(timeout: 5))
        app.buttons["historyButton"].tap()
        XCTAssertTrue(app.collectionViews["historyList"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.collectionViews["historyList"].cells.count, 1)
        snapshot("05-history")
        app.collectionViews["historyList"].cells.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["summaryShotCount"].waitForExistence(timeout: 5))
        snapshot("05b-history-summary")
    }

    /// A replayed clip ends like a live session: Summary then Done lands on Home, and the clip is in History.
    func testReplayDoneReturnsHomeWithHistory() {
        let clip = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/side.keypoints.json").path
        app.terminate()
        app.launchArguments = ["-ui-testing", "-replay-keypoints", clip, "-replay-label", "side-real"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any)["replayComplete"].waitForExistence(timeout: 30))
        rotate(.landscapeLeft)
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.staticTexts["cueBanner"].waitForExistence(timeout: 5))
        snapshot("06-replay-landscape")
        rotate(.portrait)
        snapshot("06b-replay-complete")
        app.buttons["endSessionButton"].tap()
        XCTAssertTrue(app.buttons["summaryDoneButton"].waitForExistence(timeout: 5))
        snapshot("06c-replay-summary")
        app.buttons["summaryDoneButton"].tap()
        XCTAssertTrue(app.buttons["historyButton"].waitForExistence(timeout: 5))
        app.buttons["historyButton"].tap()
        XCTAssertTrue(app.collectionViews["historyList"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.collectionViews["historyList"].cells.count, 1)
        snapshot("06d-replay-history")
    }

    func testEndingWithoutShotsReturnsHome() {
        // On a slow runner the demo shooter can land a shot before End is tapped, so keep it idle.
        app.terminate()
        app.launchArguments = ["-ui-testing", "-demo-idle"]
        app.launch()
        app.buttons["startButton"].tap()
        app.buttons["goLiveButton"].tap()
        XCTAssertTrue(app.buttons["endSessionButton"].waitForExistence(timeout: 5))
        app.buttons["endSessionButton"].tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["lastSessionCard"].exists)
    }

    func testCancelSetup() {
        app.buttons["startButton"].tap()
        XCTAssertTrue(app.buttons["cancelSetupButton"].waitForExistence(timeout: 5))
        app.buttons["cancelSetupButton"].tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5))
    }

    func testEmptyHistory() {
        app.buttons["historyButton"].tap()
        XCTAssertTrue(app.staticTexts["No sessions yet"].waitForExistence(timeout: 5))
    }

    func testSettings() {
        app.buttons["settingsButton"].tap()
        let toggle = app.switches["voiceSetting"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        snapshot("06-settings")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["settingsDoneButton"].tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5))
    }

    func testGhostReplayAfterEachShot() {
        app.buttons["settingsButton"].tap()
        let toggle = app.switches["ghostReplaySetting"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        snapshot("07-settings-ghost-replay")
        app.buttons["settingsDoneButton"].tap()

        app.buttons["startButton"].tap()
        XCTAssertTrue(app.buttons["goLiveButton"].waitForExistence(timeout: 5))
        app.segmentedControls["cameraViewPicker"].buttons["Side on"].tap()
        app.buttons["goLiveButton"].tap()
        let count = app.staticTexts["shotCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label.integerValue >= 2"), evaluatedWith: count)
        waitForExpectations(timeout: 60)
        let legend = app.descendants(matching: .any)["ghostReplayLegend"]
        XCTAssertTrue(legend.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Best'")).firstMatch.waitForExistence(timeout: 10))
        snapshot("08-ghost-replay")

        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        XCTAssertTrue(app.descendants(matching: .any)["ghostReplayLegend"].waitForExistence(timeout: 10))
        snapshot("08b-ghost-replay-landscape")
    }

    func testGhostReplayIsOffByDefault() {
        app.buttons["startButton"].tap()
        app.buttons["goLiveButton"].tap()
        let count = app.staticTexts["shotCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label.integerValue >= 1"), evaluatedWith: count)
        waitForExpectations(timeout: 60)
        XCTAssertFalse(app.descendants(matching: .any)["ghostReplayLegend"].exists)
    }
}
