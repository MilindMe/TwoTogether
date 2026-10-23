import XCTest
@testable import HabitCore

final class GrowthTests: XCTestCase {
    func habit(start: String = "2026-10-01", weekdays: String = "[1,2,3,4,5,6,7]") throws -> Habit {
        try JSONDecoder().decode(Habit.self, from: Data("""
        {"id":"walk","owner":"alex","name":"Walk","icon":"figure.walk","color":"green","start":"\(start)","archive":null,"schedules":[{"effective":"\(start)","weekdays":\(weekdays)}]}
        """.utf8))
    }
    func testNewHabitIsAHealthySeed() throws {
        let g = Tracking.growth(habit: try habit(), today: "2026-10-01") { _ in false }
        XCTAssertEqual(g.stage, .seed); XCTAssertEqual(g.points, 0); XCTAssertEqual(g.vitality, 1); XCTAssertFalse(g.wilting)
    }
    func testRunsGrowFasterThanScatteredCheckIns() throws {
        let h = try habit()
        // Seven days in a row: 1 + 8/7 + … + 13/7 = 7 + 21/7 = 10 points.
        let run = Tracking.growth(habit: h, today: "2026-10-07") { _ in true }
        XCTAssertEqual(run.points, 10, accuracy: 0.0001); XCTAssertEqual(run.stage, .sapling); XCTAssertEqual(run.bestStreak, 7)
        // Every other day: seven check-ins, each a run of one. The open 14th is excluded from vitality.
        let scattered = Tracking.growth(habit: h, today: "2026-10-14") { Int($0.suffix(2))! % 2 == 1 }
        XCTAssertEqual(scattered.points, 7, accuracy: 0.0001); XCTAssertEqual(scattered.stage, .sprout)
        XCTAssertEqual(scattered.vitality, 7.0 / 13, accuracy: 0.0001)
    }
    func testRunBonusIsCappedAtThreePoints() throws {
        let g = Tracking.growth(habit: try habit(), today: "2026-10-30") { _ in true }
        // Days 1–15 earn 1…3 (sum 30); days 16–30 earn 3 each.
        XCTAssertEqual(g.points, 30 + 45, accuracy: 0.0001); XCTAssertEqual(g.stage, .mature)
    }
    func testMissesWiltButNeverShrink() throws {
        let h = try habit()
        let before = Tracking.growth(habit: h, today: "2026-10-05") { _ in true }
        let after = Tracking.growth(habit: h, today: "2026-10-20") { $0 <= "2026-10-05" }
        XCTAssertEqual(before.points, after.points)
        XCTAssertEqual(after.vitality, 0, accuracy: 0.0001); XCTAssertTrue(after.wilting)
    }
    func testRestDaysAndOpenTodayDontCount() throws {
        // Weekdays only; 2026-10-05 is a Monday.
        let h = try habit(start: "2026-10-05", weekdays: "[1,2,3,4,5]")
        let g = Tracking.growth(habit: h, today: "2026-10-12") { $0 < "2026-10-10" }
        XCTAssertEqual(g.bestStreak, 5); XCTAssertEqual(g.vitality, 1)
    }
    func testStageProgressAndLevel() {
        XCTAssertEqual(Growth(points: 17.5).stage, .sapling)
        XCTAssertEqual(Growth(points: 17.5).progress, 0.5, accuracy: 0.0001)
        XCTAssertEqual(Growth(points: 17.5).level, 2.5, accuracy: 0.0001)
        XCTAssertEqual(Growth(points: 500).stage, .ancient)
        XCTAssertEqual(Growth(points: 500).progress, 1)
    }
}
