import XCTest

final class BuskUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
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

        XCUIDevice.shared.orientation = .landscapeLeft
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

    /// Hands-free flow: the simulator has no microphone, so the on-screen voice buttons inject each phrase into the
    /// same parser the speech recognizer feeds on a device.
    func testHandsFreeVoiceCommands() {
        let status = app.staticTexts["voiceStatus"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(status.label.contains("start session"), status.label)
        snapshot("07-voice-home")

        app.buttons["simulateVoice-start"].tap()
        let count = app.staticTexts["shotCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 10), "\"start session\" goes live without touching setup")
        XCTAssertTrue(app.buttons["simulateVoice-status"].waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label.integerValue >= 2"), evaluatedWith: count)
        waitForExpectations(timeout: 60)
        snapshot("08-voice-live")

        app.buttons["simulateVoice-status"].tap()
        let spoken = app.staticTexts["lastSpokenCue"]
        let answer = NSPredicate(format: "label CONTAINS 'average form'")
        expectation(for: answer, evaluatedWith: spoken)
        waitForExpectations(timeout: 5)
        XCTAssertTrue(spoken.label.hasPrefix("Said"), spoken.label)
        XCTAssertTrue(status.label.contains("how am i doing"), status.label)
        snapshot("09-voice-how-am-i-doing")

        app.buttons["simulateVoice-end"].tap()
        XCTAssertTrue(app.staticTexts["summaryShotCount"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(Int(app.staticTexts["summaryShotCount"].label) ?? 0, 2)
        snapshot("10-voice-ended-summary")
    }

    func testVoiceCommandsSettingHidesVoiceBar() {
        XCTAssertTrue(app.staticTexts["voiceStatus"].waitForExistence(timeout: 10))
        app.buttons["settingsButton"].tap()
        let toggle = app.switches["voiceCommandsSetting"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["settingsDoneButton"].tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["voiceStatus"].exists)
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
}
