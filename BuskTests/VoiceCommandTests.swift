import XCTest
@testable import Busk

final class VoiceCommandTests: XCTestCase {
    func testParsesCommandPhrases() {
        XCTAssertEqual(VoiceCommandParser.command(in: "Start session"), .start)
        XCTAssertEqual(VoiceCommandParser.command(in: "okay busk, let's go"), .start)
        XCTAssertEqual(VoiceCommandParser.command(in: "How am I doing?"), .status)
        XCTAssertEqual(VoiceCommandParser.command(in: "how’s my form"), .status)
        XCTAssertEqual(VoiceCommandParser.command(in: "End session."), .end)
        XCTAssertEqual(VoiceCommandParser.command(in: "alright I'm done"), .end)
        XCTAssertEqual(VoiceCommandParser.command(in: "Made it!"), .make)
        XCTAssertEqual(VoiceCommandParser.command(in: "swish"), .make)
        XCTAssertEqual(VoiceCommandParser.command(in: "ugh, missed it"), .miss)
        XCTAssertEqual(VoiceCommandParser.command(in: "brick"), .miss)
    }

    func testIgnoresOrdinaryTalkAndCoachCues() {
        XCTAssertNil(VoiceCommandParser.command(in: "nice shot"))
        XCTAssertNil(VoiceCommandParser.command(in: "One smooth motion, don't stop the ball at your set point"))
        XCTAssertNil(VoiceCommandParser.command(in: "Got you. Shoot when ready"))
        XCTAssertNil(VoiceCommandParser.command(in: "restart sessions"))
        for area in FormArea.allCases {
            XCTAssertNil(VoiceCommandParser.command(in: area.cue), area.cue)
        }
    }

    func testLastCommandSaidWins() {
        XCTAssertEqual(VoiceCommandParser.command(in: "start session how am I doing"), .status)
        XCTAssertEqual(VoiceCommandParser.command(in: "how am I doing okay end session"), .end)
    }

    func testStatusAnswerDoesNotTriggerCommands() {
        let good = ShotMetrics(view: .front, setPointHeight: 0.15, elbowFlare: 0.02, armAngle: nil, followThrough: 0.8,
                               legDrive: 0.04, releaseTiming: 0, hitch: 0, drift: 0.02, guideHandPush: 0.01)
        var flared = good
        flared.elbowFlare = 0.1
        let shots = [flared, flared, good, flared, good].map { FormEvaluator().evaluate($0) }
        let summary = SessionSummary(shots: shots)
        let text = summary.spokenStatus
        XCTAssertTrue(text.hasPrefix("5 shots, average form \(summary.averageScore), best 100."), text)
        XCTAssertTrue(text.contains("elbow"), text)
        XCTAssertNil(VoiceCommandParser.command(in: text))
        XCTAssertEqual(SessionSummary(shots: []).spokenStatus, "No shots yet. Shoot when you're ready.")
    }

    @MainActor
    func testInjectedTranscriptFiresOnceAndDebounces() async {
        var now = Date(timeIntervalSince1970: 0)
        let voice = VoiceControl(simulateInput: true, clock: { now })
        XCTAssertNil(voice.heard("start session"), "ignored while off")
        await voice.start()
        XCTAssertEqual(voice.state, .simulated)

        voice.inject("start session")
        XCTAssertEqual(voice.event?.command, .start)
        XCTAssertEqual(voice.event?.id, 1)
        // The same words arrive again in the next partial result.
        voice.inject("start session")
        XCTAssertEqual(voice.event?.id, 1)

        now += 3
        voice.inject("how am I doing")
        XCTAssertEqual(voice.event, VoiceEvent(id: 2, command: .status, transcript: "how am I doing"))
        XCTAssertEqual(voice.lastHeard, "how am I doing")

        now += 3
        voice.inject("what a shot")
        XCTAssertEqual(voice.event?.id, 2)

        voice.stop()
        XCTAssertEqual(voice.state, .off)
    }
}
