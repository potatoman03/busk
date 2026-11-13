import XCTest
@testable import Busk

final class PracticeLogTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return c
    }()
    private lazy var now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 18))!
    private let good = ShotMetrics(view: .front, setPointHeight: 0.15, elbowFlare: 0.02, armAngle: nil, followThrough: 0.8,
                                   legDrive: 0.04, releaseTiming: 0, hitch: 0, drift: 0.02, guideHandPush: 0.01)

    private func shots(_ count: Int, flared: Bool = false) -> [ShotResult] {
        var m = good
        if flared { m.elbowFlare = 0.1 }
        return Array(repeating: FormEvaluator().evaluate(m), count: count)
    }

    private func entry(daysAgo: Int, shots: [ShotResult], makes: Int? = nil) -> PracticeEntry {
        PracticeEntry(date: calendar.date(byAdding: .day, value: -daysAgo, to: now)!, shots: shots, makes: makes)
    }

    func testDailyTotalsAndMakeRate() {
        let log = PracticeLog(entries: [entry(daysAgo: 0, shots: shots(20), makes: 8),
                                        entry(daysAgo: 0, shots: shots(10)),
                                        entry(daysAgo: 1, shots: shots(5), makes: 5)], now: now, calendar: calendar)
        XCTAssertEqual(log.today.sessions, 2)
        XCTAssertEqual(log.today.shots, 30)
        XCTAssertEqual(log.today.makes, 8)
        // The session with no makes logged doesn't count against the make rate.
        XCTAssertEqual(log.today.makeRate, 0.4)
        XCTAssertEqual(log.totalShots, 35)
        XCTAssertEqual(log.totalMakes, 13)
        XCTAssertEqual(log.lastDays(7).count, 7)
        XCTAssertEqual(log.lastDays(7).last?.shots, 30)
        XCTAssertEqual(log.goalDays(goal: 25, in: 7), 1)
    }

    func testStreakSurvivesUntilTheDayIsOver() {
        let log = PracticeLog(entries: [1, 2, 3, 5].map { entry(daysAgo: $0, shots: shots(3)) }, now: now, calendar: calendar)
        XCTAssertEqual(log.currentStreak, 3, "no practice yet today keeps yesterday's streak alive")
        XCTAssertEqual(log.longestStreak, 3)
        let broken = PracticeLog(entries: [2, 3].map { entry(daysAgo: $0, shots: shots(3)) }, now: now, calendar: calendar)
        XCTAssertEqual(broken.currentStreak, 0)
        XCTAssertEqual(broken.longestStreak, 2)
        XCTAssertEqual(PracticeLog(entries: [], now: now, calendar: calendar).currentStreak, 0)
    }

    func testImprovementComparesFirstAndLatestShots() {
        let log = PracticeLog(entries: [entry(daysAgo: 6, shots: shots(30, flared: true), makes: 9),
                                        entry(daysAgo: 0, shots: shots(30), makes: 15)], now: now, calendar: calendar)
        let (then, latest) = try! XCTUnwrap(log.improvement())
        XCTAssertLessThan(then.averageScore, latest.averageScore)
        XCTAssertEqual(then.goodRate[.elbow], 0)
        XCTAssertEqual(latest.goodRate[.elbow], 1)
        XCTAssertEqual(try XCTUnwrap(then.makeRate), 0.3, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(latest.makeRate), 0.5, accuracy: 1e-9)
        XCTAssertEqual(log.focus(lastShots: 60), .elbow)
        XCTAssertNil(PracticeLog(entries: [entry(daysAgo: 0, shots: shots(40))], now: now, calendar: calendar).improvement(),
                     "one session is nothing to compare")
    }

    func testLatestMakeRateIsOverThoseShotsAndSkipsUnmarked() {
        let missed = shots(40).map { var s = $0; s.made = false; return s }
        let made = shots(20).map { var s = $0; s.made = true; return s }
        let log = PracticeLog(entries: [entry(daysAgo: 3, shots: missed), entry(daysAgo: 0, shots: made + shots(5))],
                              now: now, calendar: calendar)
        let (then, latest) = try! XCTUnwrap(log.improvement())
        XCTAssertEqual(then.makeRate, 0)
        // Latest 30: 5 missed from the older session, 20 made and 5 never marked.
        XCTAssertEqual(try XCTUnwrap(latest.makeRate), 0.8, accuracy: 1e-9)
        XCTAssertEqual(log.today.makes, 20)
        XCTAssertEqual(log.today.trackedShots, 20)
        XCTAssertEqual(log.today.makeRate, 1)
    }

    func testWeekOverWeek() {
        let log = PracticeLog(entries: [entry(daysAgo: 0, shots: shots(10)), entry(daysAgo: 6, shots: shots(10)),
                                        entry(daysAgo: 7, shots: shots(4)), entry(daysAgo: 14, shots: shots(50))],
                              now: now, calendar: calendar)
        XCTAssertEqual(log.thisWeek.shots, 20)
        XCTAssertEqual(log.thisWeek.sessions, 2)
        XCTAssertEqual(log.lastWeek.shots, 4)
        XCTAssertEqual(log.mostShotsInADay, 50)
    }

    func testSummaryMakesFromMarkedShots() {
        var marked = shots(4)
        XCTAssertNil(SessionSummary(shots: marked).makes, "nothing marked means makes weren't logged, not zero")
        marked[0].made = true
        marked[1].made = false
        marked[2].made = true
        let summary = SessionSummary(shots: marked)
        XCTAssertEqual(summary.makes, 2)
        XCTAssertEqual(summary.attempts, 3)
        XCTAssertEqual(summary.unmarked, 1)
        XCTAssertEqual(try XCTUnwrap(summary.makeRate), 2.0 / 3, accuracy: 1e-9, "the unmarked shot isn't a miss")
        let whole = SessionSummary(shots: marked, makes: 3)
        XCTAssertEqual(whole.makes, 3, "a count for the whole session wins over the marks")
        XCTAssertEqual(whole.makeRate, 0.75)
        XCTAssertEqual(whole.unmarked, 0)
        XCTAssertTrue(summary.spokenStatus.contains("2 of 3 went in."), summary.spokenStatus)
        XCTAssertNil(VoiceCommandParser.command(in: summary.spokenStatus))
    }
}
