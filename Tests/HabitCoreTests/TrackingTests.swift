import XCTest
@testable import HabitCore

final class TrackingTests: XCTestCase {
    func habit(_ schedule: String = "[{\"effective\":\"2026-10-22\",\"weekdays\":[1,2,3,4,5,6,7]}]", archive: String = "null") throws -> Habit {
        let json = """
        {"id":"walk","owner":"alex","name":"Walk","icon":"figure.walk","color":"green","start":"2026-10-22","archive":\(archive),"schedules":\(schedule)}
        """
        return try JSONDecoder().decode(Habit.self, from: Data(json.utf8))
    }
    func testWeekIsMondayToSundayAcrossYearBoundary() {
        XCTAssertEqual(Tracking.week(containing: "2027-01-01"), ["2026-12-28", "2026-12-29", "2026-12-30", "2026-12-31", "2027-01-01", "2027-01-02", "2027-01-03"])
    }
    func testFutureDatesExcludedAndNewHabitsDontCreateMisses() throws {
        let h = try habit()
        let t = Tracking.totals(habit: h, dates: Tracking.week(containing: "2026-10-22"), today: "2026-10-22") { _ in true }
        XCTAssertEqual(t.done, 1); XCTAssertEqual(t.elapsed, 1)
        XCTAssertEqual(Tracking.state(habit: h, date: "2026-10-21", today: "2026-10-22", completed: false), .unscheduled)
        XCTAssertEqual(Tracking.state(habit: h, date: "2026-10-22", today: "2026-10-22", completed: false), .open)
        XCTAssertEqual(Tracking.state(habit: h, date: "2026-10-23", today: "2026-10-22", completed: false), .upcoming)
        XCTAssertEqual(Tracking.state(habit: h, date: "2026-10-22", today: "2026-10-23", completed: false), .missed)
    }
    func testHistoricalScheduleAndArchive() throws {
        let h = try habit("[{\"effective\":\"2026-10-22\",\"weekdays\":[4]},{\"effective\":\"2026-10-23\",\"weekdays\":[5]}]", archive: "\"2026-10-24\"")
        XCTAssertTrue(h.isScheduled("2026-10-22")); XCTAssertTrue(h.isScheduled("2026-10-23"))
        XCTAssertFalse(h.isScheduled("2026-10-24")); XCTAssertFalse(h.isScheduled("2026-10-30"))
        let t = Tracking.totals(habit: h, dates: Tracking.week(containing: "2026-10-22"), today: "2026-10-25") { $0 == "2026-10-22" }
        XCTAssertEqual(t.done, 1); XCTAssertEqual(t.elapsed, 2)
    }
    func testTrackingTimezoneIgnoresTravelAndHandlesDST() {
        let f = ISO8601DateFormatter()
        for (stamp, expected) in [("2026-10-23T03:59:59Z", "2026-10-22"), ("2026-10-23T04:00:00Z", "2026-10-23"), ("2026-11-01T05:30:00Z", "2026-11-01"), ("2026-11-01T06:30:00Z", "2026-11-01")] {
            XCTAssertEqual(Tracking.today(now: f.date(from: stamp)!, timezone: "America/Toronto"), expected)
        }
        XCTAssertEqual(Tracking.adding(1, to: "2026-11-01"), "2026-11-02")
    }
    func testOfflineOutboxPersistsAndLatestTapWins() throws {
        let snapshot = try JSONDecoder().decode(Snapshot.self, from: Data("""
        {"me":"alex","timezone":"America/Toronto","today":"2026-10-22","people":[],"habits":[],"completions":[],"nudges":[]}
        """.utf8))
        let ops = [PendingCompletion(habit: "walk", date: "2026-10-22", completed: true), PendingCompletion(habit: "walk", date: "2026-10-22", completed: false), PendingCompletion(habit: "walk", date: "2026-10-22", completed: true)]
        let saved = try JSONEncoder().encode(ops)
        let restored = try JSONDecoder().decode([PendingCompletion].self, from: saved)
        XCTAssertEqual(restored.map(\.id), ops.map(\.id))
        XCTAssertTrue(Tracking.completed("walk", on: "2026-10-22", snapshot: snapshot, pending: restored))
        XCTAssertFalse(Tracking.completed("walk", on: "2026-10-22", snapshot: snapshot, pending: Array(restored.prefix(2))))
    }
}
