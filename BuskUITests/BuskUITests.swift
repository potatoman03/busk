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
        XCTAssertTrue(app.buttons["startButton"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["startButton"].exists)
        XCTAssertTrue(app.buttons["settingsButton"].exists)
        XCTAssertTrue(app.buttons["historyButton"].exists)
        XCTAssertTrue(app.staticTexts["Elbow"].exists)
        XCTAssertTrue(app.staticTexts["Balance"].exists)
        XCTAssertTrue(app.staticTexts["Legs"].exists)
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
        XCTAssertTrue(check.waitForExistence(timeout: 8))
        snapshot("framing-check")
        let banner = app.staticTexts["cueBanner"]
        XCTAssertFalse(banner.label.hasPrefix("Got you"), banner.label)
        expectation(for: NSPredicate(format: "label BEGINSWITH 'Got you'"), evaluatedWith: banner)
        waitForExpectations(timeout: 30)
        XCTAssertFalse(check.exists)
    }

    func testPracticeProgress() {
        relaunch(["-ui-testing", "-seed-practice", "21"])
        let today = app.buttons["todayCard"]
        XCTAssertTrue(today.waitForExistence(timeout: 10))
        XCTAssertTrue(app.descendants(matching: .any)["streakCount"].exists)
        snapshot("06-home-tracker")

        today.tap()
        XCTAssertTrue(app.staticTexts["progressTotalShots"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(Int(app.staticTexts["progressTotalShots"].label.filter(\.isNumber)) ?? 0, 100)
        XCTAssertTrue(app.descendants(matching: .any)["practiceCalendar"].exists)
        snapshot("07-progress-top")
        let scroll = app.scrollViews["progressScroll"]
        scroll.swipeUp()
        snapshot("08-progress-charts")
        scroll.swipeUp()
        scroll.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["improvementCard"].waitForExistence(timeout: 3))
        snapshot("09-progress-improvement")
        scroll.swipeUp()
        XCTAssertTrue(app.descendants(matching: .any)["personalBests"].waitForExistence(timeout: 3))
        snapshot("10-progress-bests")
    }

    func testEmptyProgress() {
        app.buttons["progressButton"].tap()
        XCTAssertTrue(app.staticTexts["No practice yet"].waitForExistence(timeout: 5))
        snapshot("11-progress-empty")
    }

    func testCountingWholeSessionCanGoBackToMarks() {
        app.buttons["startButton"].tap()
        XCTAssertTrue(app.buttons["goLiveButton"].waitForExistence(timeout: 5))
        app.buttons["goLiveButton"].tap()
        XCTAssertTrue(app.buttons["markMadeButton"].waitForExistence(timeout: 30))
        app.buttons["endSessionButton"].tap()

        let summaryMakes = app.staticTexts["summaryMakes"]
        XCTAssertTrue(summaryMakes.waitForExistence(timeout: 5))
        let stepper = app.steppers["makesStepper"]
        XCTAssertTrue(stepper.exists, "nothing marked, so the whole session can be counted")
        let firstMark = app.buttons["shotMark-1"]
        XCTAssertTrue(firstMark.exists)
        stepper.buttons.element(boundBy: 1).tap()
        XCTAssertEqual(summaryMakes.label, "1")
        XCTAssertFalse(firstMark.exists, "a whole-session count hides the shot marks")
        XCTAssertTrue(app.buttons["useShotMarksButton"].exists, "a counted session can always go back to shot marks")
        stepper.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(firstMark.waitForExistence(timeout: 2), "counting back to 0 brings the shot marks back")
        XCTAssertFalse(app.buttons["useShotMarksButton"].exists)

        stepper.buttons.element(boundBy: 1).tap()
        app.buttons["useShotMarksButton"].tap()
        XCTAssertTrue(firstMark.waitForExistence(timeout: 2))
        XCTAssertEqual(firstMark.label, "Not marked")
        snapshot("13c-summary-count-way-back")
    }

    func testMarkingMakesDuringSession() {
        app.buttons["startButton"].tap()
        XCTAssertTrue(app.buttons["goLiveButton"].waitForExistence(timeout: 5))
        app.buttons["goLiveButton"].tap()
        let made = app.buttons["markMadeButton"]
        XCTAssertTrue(made.waitForExistence(timeout: 30))
        made.tap()
        let makes = app.staticTexts["makeCount"]
        XCTAssertTrue(makes.waitForExistence(timeout: 5))
        XCTAssertEqual(makes.label, "1")
        snapshot("12-live-made")
        app.buttons["endSessionButton"].tap()

        XCTAssertTrue(app.staticTexts["summaryMakes"].waitForExistence(timeout: 5))
        let summaryMakes = app.staticTexts["summaryMakes"]
        XCTAssertEqual(summaryMakes.label, "1", "the live make is kept")
        XCTAssertFalse(app.steppers["makesStepper"].exists, "marked shots are changed one by one, not by a count")
        let madeMark = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'shotMark-' AND label == 'Made'")).firstMatch
        XCTAssertTrue(madeMark.exists, "the shot list marks the made shot")
        let mark = app.buttons[madeMark.identifier]
        mark.tap()
        XCTAssertEqual(mark.label, "Missed")
        XCTAssertEqual(summaryMakes.label, "0")
        mark.tap()
        XCTAssertEqual(mark.label, "Not marked")
        mark.tap()
        XCTAssertEqual(mark.label, "Made")
        XCTAssertEqual(summaryMakes.label, "1")

        app.buttons["countWholeButton"].tap()
        let stepper = app.steppers["makesStepper"]
        XCTAssertTrue(stepper.waitForExistence(timeout: 2))
        XCTAssertFalse(mark.exists, "a whole-session count hides the shot marks it would disagree with")
        stepper.buttons.element(boundBy: 0).tap()
        XCTAssertEqual(summaryMakes.label, "0")
        app.buttons["useShotMarksButton"].tap()
        XCTAssertEqual(summaryMakes.label, "1")
        XCTAssertEqual(mark.label, "Made")
        XCTAssertTrue(app.descendants(matching: .any)["summaryDemoNote"].exists, "demo sessions stay out of the tracker")
        snapshot("13-summary-makes")
        app.swipeUp()
        snapshot("13b-summary-shot-marks")
        app.buttons["summaryDoneButton"].tap()
        XCTAssertTrue(app.buttons["todayCard"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["demoTag"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["todayShots"].label.hasPrefix("0"), true, app.descendants(matching: .any)["todayShots"].label)
        snapshot("14-home-after-session")
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
        // Ending saves the session and releases the audio session, which is slow on CI simulators.
        XCTAssertTrue(app.staticTexts["summaryShotCount"].waitForExistence(timeout: 15))
        XCUIDevice.shared.orientation = .portrait
        XCTAssertGreaterThanOrEqual(Int(app.staticTexts["summaryShotCount"].label) ?? 0, 2)
        snapshot("04-summary")
        app.buttons["summaryDoneButton"].tap()

        XCTAssertTrue(app.buttons["lastSessionCard"].waitForExistence(timeout: 5))
        app.buttons["historyButton"].tap()
        XCTAssertTrue(app.collectionViews["historyList"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.collectionViews["historyList"].buttons.matching(identifier: "historyRow").count, 1)
        XCTAssertTrue(app.descendants(matching: .any)["historyDayHeader"].exists)
        snapshot("05-history")
        app.collectionViews["historyList"].buttons["historyRow"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["summaryShotCount"].waitForExistence(timeout: 5))
        snapshot("05b-history-summary")
        app.buttons["shotRow-1"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Shot 1"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["shotDetailScore"].exists)
        snapshot("05c-shot-detail")
    }

    /// Hands-free flow: the simulator has no microphone, so the on-screen voice buttons inject each phrase into the
    /// same parser the speech recognizer feeds on a device.
    /// Drills Busk can't watch say so, and the wall flick shows where to stand.
    func testDrillInstructions() {
        relaunch(["-ui-testing"])
        let coach = app.buttons["coachCard"]
        XCTAssertTrue(coach.waitForExistence(timeout: 10))
        coach.tap()
        app.swipeUp()
        app.buttons["libraryLink"].tap()
        XCTAssertTrue(app.buttons["lesson-legs"].waitForExistence(timeout: 5))
        let lesson = app.buttons["lesson-followThrough"]
        for _ in 0..<4 where !lesson.isHittable { app.swipeUp() }
        lesson.tap()
        let drill = app.buttons["drill-wallFlick"]
        for _ in 0..<3 where !drill.isHittable { app.swipeUp() }
        drill.tap()
        XCTAssertTrue(app.descendants(matching: .any)["wallFlickPicture"].waitForExistence(timeout: 5))
        snapshot("17-wall-flick")
        app.swipeUp()
        let note = app.staticTexts["drillTrackingNote"]
        XCTAssertTrue(note.waitForExistence(timeout: 5))
        XCTAssertTrue(note.label.contains("Mark done"), note.label)
        snapshot("18-wall-flick-note")
        for (lessonID, drillID) in [("legs", "dipRise"), ("guideHand", "guideOff")] {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let next = app.buttons["lesson-\(lessonID)"]
            for _ in 0..<4 where !next.isHittable { app.swipeDown() }
            for _ in 0..<4 where !next.isHittable { app.swipeUp() }
            next.tap()
            XCTAssertTrue(app.staticTexts["\(lessonID == "legs" ? "Shoot with your legs" : "Quiet guide hand")"].firstMatch.waitForExistence(timeout: 5))
            snapshot("19-lesson-\(lessonID)")
            let d = app.buttons["drill-\(drillID)"]
            for _ in 0..<3 where !d.isHittable { app.swipeUp() }
            d.tap()
            XCTAssertTrue(app.staticTexts["drillTitle"].waitForExistence(timeout: 5))
            snapshot("19-drill-\(drillID)")
        }
    }

    /// "Start session" said on a focus set's Setup goes live there, after a session has already been shot.
    func testVoiceStartFromFocusSetSetup() {
        relaunch(["-ui-testing", "-voiceCommands", "YES"])
        for _ in 0..<2 {
            let coach = app.buttons["coachCard"]
            XCTAssertTrue(coach.waitForExistence(timeout: 10))
            coach.tap()
            app.swipeUp()
            app.buttons["libraryLink"].tap()
            let legs = app.buttons["lesson-legs"]
            XCTAssertTrue(legs.waitForExistence(timeout: 5))
            legs.tap()
            let practise = app.buttons["practiseLessonButton"]
            XCTAssertTrue(practise.waitForExistence(timeout: 5))
            practise.tap()
            XCTAssertTrue(app.buttons["goLiveButton"].waitForExistence(timeout: 5))
            app.buttons["simulateVoice-start"].firstMatch.tap()
            let count = app.staticTexts["shotCount"]
            XCTAssertTrue(count.waitForExistence(timeout: 10))
            expectation(for: NSPredicate(format: "label.integerValue >= 1"), evaluatedWith: count)
            waitForExpectations(timeout: 30)
            app.buttons["endSessionButton"].tap()
            let done = app.buttons["summaryDoneButton"]
            if done.waitForExistence(timeout: 5) { done.tap() }
            // Back to Home for the next round.
            while app.navigationBars.buttons.count > 0 && !app.buttons["coachCard"].isHittable {
                app.navigationBars.buttons.element(boundBy: 0).tap()
            }
        }
    }

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

        app.buttons["simulateVoice-make"].tap()
        XCTAssertTrue(app.staticTexts["makeCount"].waitForExistence(timeout: 5), "\"made it\" marks the last shot")
        snapshot("09b-voice-made-it")
        sleep(2) // voice commands within 1.5 s of the last one are ignored as echoes
        app.buttons["simulateVoice-miss"].tap()
        XCTAssertTrue(status.label.contains("missed it"), status.label)

        sleep(2)
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
        XCTAssertEqual(app.collectionViews["historyList"].buttons.matching(identifier: "historyRow").count, 1)
        XCTAssertTrue(app.descendants(matching: .any)["historyDayHeader"].exists)
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
        XCTAssertTrue(app.alerts["No shots tracked"].waitForExistence(timeout: 5))
        snapshot("08-no-shots-alert")
        app.alerts.buttons["OK"].tap()
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
        app.buttons["testVoiceButton"].tap()
        XCTAssertTrue(app.staticTexts["testVoiceSpeaking"].waitForExistence(timeout: 5))
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
        expectation(for: NSPredicate(format: "value == '1'"), evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
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
