import XCTest
@testable import HabitCore
final class CacheTests: XCTestCase {
    func testPendingCheckinsSurviveReopeningAndRemainOrdered() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("state.json")
        let first = PendingCompletion(habit: "walk", date: "2026-10-22", completed: true)
        let second = PendingCompletion(habit: "walk", date: "2026-10-22", completed: false)
        let original = LocalCache(url: url)
        try original.save(CachedState(pending: [first, second]))
        let reopened = try LocalCache(url: url).load()
        XCTAssertEqual(reopened.pending.map(\.id), [first.id, second.id])
        XCTAssertEqual(reopened.pending.map(\.completed), [true, false])
        var acknowledged = reopened
        acknowledged.pending.removeFirst()
        try LocalCache(url: url).save(acknowledged)
        XCTAssertEqual(try LocalCache(url: url).load().pending.map(\.id), [second.id])
    }
    func testEmptyCacheAndCorruptionAreDifferent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let cache = LocalCache(url: folder.appendingPathComponent("state.json"))
        XCTAssertTrue(try cache.load().pending.isEmpty)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("corrupted".utf8).write(to: cache.url)
        XCTAssertThrowsError(try cache.load())
    }
}
