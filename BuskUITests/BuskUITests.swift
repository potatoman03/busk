import XCTest

final class BuskUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }

    private func relaunch(_ arguments: [String]) {
        app.terminate()
        app.launchArguments = arguments
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
        XCTAssertTrue(app.staticTexts["Balance"].exists)
        snapshot("01-home")
    }

    func testFirstRunGuide() {
        relaunch(["-ui-testing", "-show-guide"])
        let next = app.buttons["guideNextButton"]
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Set your phone up"].exists)
        snapshot("00a-guide-phone")
        next.tap()
        XCTAssertTrue(app.staticTexts["Pick an angle"].waitForExistence(timeout: 5))
        snapshot("00b-guide-angle")
        next.tap()
        XCTAssertTrue(app.staticTexts["While you shoot"].waitForExistence(timeout: 5))
        snapshot("00c-guide-live")
        next.tap()
        XCTAssertTrue(app.staticTexts["Your coach"].waitForExistence(timeout: 5))
        snapshot("00d-guide-coach")
        next.tap()
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 5))
    }

    func testFramingCheckBeforeFirstShot() {
        relaunch(["-ui-testing", "-demo-walk-in"])
        app.buttons["startButton"].tap()
        XCTAssertTrue(app.buttons["goLiveButton"].waitForExistence(timeout: 5))
        app.buttons["goLiveButton"].tap()
        let check = app.descendants(matching: .any)["framingCheck"]
        XCTAssertTrue(check.waitForExistence(timeout: 5))
        snapshot("framing-check")
        let banner = app.staticTexts["cueBanner"]
        XCTAssertFalse(banner.label.hasPrefix("Got you"), banner.label)
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Got you'"), evaluatedWith: banner)
        waitForExpectations(timeout: 15)
        XCTAssertFalse(check.exists)
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

    /// Hands-free flow: the simulator has no microphone, so the on-screen voice buttons inject each phrase into the
    /// same parser the speech recognizer feeds on a device.
    func testHandsFreeVoiceCommands() {
        relaunch(["-ui-testing", "-voiceCommands", "YES"])
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

        // The landscape column is shorter, but the score stays on screen beside the voice bar.
        rotate(.landscapeLeft)
        XCTAssertTrue(app.staticTexts["lastShotScore"].waitForExistence(timeout: 5))
        snapshot("08b-voice-live-landscape")
        rotate(.portrait)

        app.buttons["simulateVoice-status"].tap()
        // Wait on the answer first: it only holds the cue log for a few seconds before the next shot's cue.
        let spoken = app.staticTexts["lastSpokenCue"]
        // The answer is spoken, not muted; checked in the same match since the next shot's cue can replace it at once.
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Said' AND label CONTAINS 'average form'"), evaluatedWith: spoken)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(status.label.contains("how am i doing"), status.label)
        snapshot("09-voice-how-am-i-doing")

        app.buttons["simulateVoice-end"].tap()
        XCTAssertTrue(app.staticTexts["summaryShotCount"].waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(Int(app.staticTexts["summaryShotCount"].label) ?? 0, 2)
        snapshot("10-voice-ended-summary")
    }

    /// Voice commands are an off-by-default prototype: no voice bar (and no mic prompt) until Settings turns them on.
    func testVoiceCommandsSettingShowsVoiceBar() {
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["voiceStatus"].exists)
        app.buttons["settingsButton"].tap()
        let toggle = app.switches["voiceCommandsSetting"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "0")
        snapshot("11-voice-prototype-setting")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.buttons["settingsDoneButton"].tap()
        XCTAssertTrue(app.staticTexts["voiceStatus"].firstMatch.waitForExistence(timeout: 5))
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

    func testCoachPlanAndLessons() {
        let coach = app.buttons["coachCard"]
        XCTAssertTrue(coach.waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["homeCoachFocus"].label, "Find your first focus")
        coach.tap()
        XCTAssertTrue(app.staticTexts["coachFocus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["coachFocus"].label, "Let's find your first focus")
        XCTAssertTrue(app.buttons["step-baseline"].exists)
        XCTAssertTrue(app.staticTexts["Baseline: 15 shadow shots"].exists)
        snapshot("09-coach-start")

        app.segmentedControls["hasBallPicker"].buttons["I have a ball"].tap()
        XCTAssertTrue(app.staticTexts["Baseline: 15 shots"].waitForExistence(timeout: 5))
        app.segmentedControls["hasBallPicker"].buttons["No ball"].tap()

        app.buttons["step-lesson-overview"].tap()
        XCTAssertTrue(app.staticTexts["lessonTitle"].waitForExistence(timeout: 5))
        snapshot("10-lesson-overview")
        XCTAssertTrue(app.descendants(matching: .any)["ballPosition-setPoint"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(app.staticTexts["workoutProgress"].label, "1/2")

        app.swipeUp()
        app.buttons["libraryLink"].tap()
        let elbow = app.buttons["lesson-elbow"]
        XCTAssertTrue(elbow.waitForExistence(timeout: 5))
        snapshot("11-library")
        elbow.tap()
        XCTAssertTrue(app.staticTexts["lessonTitle"].label.hasPrefix("Elbow"))
        snapshot("12-lesson-elbow")
        app.swipeUp()
        let drill = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'drill-'")).firstMatch
        XCTAssertTrue(drill.waitForExistence(timeout: 5))
        drill.tap()
        XCTAssertTrue(app.staticTexts["drillTitle"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["drillDoneButton"].exists)
        snapshot("13-drill")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // A focus set from the lesson: Busk only coaches the elbow and the plan keeps it as the focus.
        let practise = app.buttons["practiseLessonButton"]
        XCTAssertTrue(practise.waitForExistence(timeout: 5))
        practise.tap()
        XCTAssertTrue(app.otherElements["setupFocusCard"].waitForExistence(timeout: 5) || app.staticTexts["Focus set"].exists)
        snapshot("14-focus-setup")
        app.buttons["goLiveButton"].tap()
        let pill = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Elbow '")).firstMatch
        let count = app.staticTexts["shotCount"]
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        expectation(for: NSPredicate(format: "label.integerValue >= 2"), evaluatedWith: count)
        waitForExpectations(timeout: 60)
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        snapshot("15-focus-live")
        app.buttons["endSessionButton"].tap()
        XCTAssertTrue(app.staticTexts["summaryFocusResult"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["summaryFocusResult"].label.hasPrefix("Elbow"))
        snapshot("16-focus-summary")
        app.buttons["summaryDoneButton"].tap()

        while app.navigationBars.buttons.count > 0 && !app.navigationBars["Busk"].exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        XCTAssertTrue(app.staticTexts["homeCoachFocus"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["homeCoachFocus"].label, "Focus: Elbow")
        app.buttons["coachCard"].tap()
        XCTAssertEqual(app.staticTexts["coachFocus"].label, "Elbow")
        XCTAssertTrue(app.buttons["step-focus-elbow"].exists)
        snapshot("17-coach-focus")
    }
}
