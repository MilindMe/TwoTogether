import Foundation

public struct Person: Codable, Identifiable, Sendable { public var id: String; public var name: String }
public struct Schedule: Codable, Sendable { public var effective: String; public var weekdays: [Int] }
public struct Habit: Codable, Identifiable, Sendable {
    public var id: String
    public var owner: String
    public var name: String
    public var icon: String
    public var color: String
    public var start: String
    public var archive: String?
    public var schedules: [Schedule]
    public func isScheduled(_ date: String) -> Bool {
        guard date >= start, archive.map({ date < $0 }) ?? true,
              let day = Tracking.date(date),
              let schedule = schedules.filter({ $0.effective <= date }).max(by: { $0.effective < $1.effective }) else { return false }
        let weekday = Tracking.calendar.component(.weekday, from: day)
        return schedule.weekdays.contains((weekday + 5) % 7 + 1)
    }
}
public struct Completion: Codable, Sendable { public var habit: String; public var date: String; public var completed_at: String }
public struct Nudge: Codable, Identifiable, Sendable {
    public var id: String; public var sender: String; public var recipient: String
    public var habit: String; public var date: String; public var created_at: String
    public var delivery: String; public var read: Int
}
public struct Snapshot: Codable, Sendable {
    public var me: String; public var timezone: String; public var today: String
    public var people: [Person]; public var habits: [Habit]
    public var completions: [Completion]; public var nudges: [Nudge]
}
public struct PendingCompletion: Codable, Identifiable, Sendable {
    public var id: String; public var habit: String; public var date: String; public var completed: Bool
    public init(habit: String, date: String, completed: Bool) {
        self.id = UUID().uuidString; self.habit = habit; self.date = date; self.completed = completed
    }
}
public enum CellState: String, Sendable { case completed, missed, upcoming, unscheduled, open }
public enum Tracking {
    // Civil dates are parsed at noon UTC. Date arithmetic never depends on device timezone or DST.
    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; c.firstWeekday = 2; return c
    }
    public static func date(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
    public static func key(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
    public static func today(now: Date = Date(), timezone: String) -> String {
        var c = calendar; c.timeZone = TimeZone(identifier: timezone) ?? TimeZone(identifier: "America/Toronto")!
        let p = c.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }
    public static func adding(_ days: Int, to key: String) -> String {
        self.key(calendar.date(byAdding: .day, value: days, to: date(key)!)!)
    }
    public static func week(containing key: String, offset: Int = 0) -> [String] {
        let d = date(key)!
        let weekday = (calendar.component(.weekday, from: d) + 5) % 7
        let monday = adding(-weekday + offset * 7, to: key)
        return (0..<7).map { adding($0, to: monday) }
    }
    public static func completed(_ habit: String, on date: String, snapshot: Snapshot, pending: [PendingCompletion]) -> Bool {
        pending.last(where: { $0.habit == habit && $0.date == date })?.completed ?? snapshot.completions.contains { $0.habit == habit && $0.date == date }
    }
    public static func state(habit: Habit, date: String, today: String, completed: Bool) -> CellState {
        guard habit.isScheduled(date) else { return .unscheduled }
        if date > today { return .upcoming }
        if completed { return .completed }
        return date < today ? .missed : .open
    }
    public static func totals(habit: Habit, dates: [String], today: String, isComplete: (String) -> Bool) -> (done: Int, elapsed: Int) {
        let elapsed = dates.filter { $0 <= today && habit.isScheduled($0) }
        return (elapsed.filter(isComplete).count, elapsed.count)
    }
    // Consecutive completed scheduled days. An open today doesn't break the streak; rest days are skipped.
    public static func streak(habit: Habit, today: String, isComplete: (String) -> Bool) -> Int {
        var date = isComplete(today) ? today : adding(-1, to: today), count = 0
        while date >= habit.start {
            if habit.isScheduled(date) { guard isComplete(date) else { break }; count += 1 }
            date = adding(-1, to: date)
        }
        return count
    }
}

public struct CachedState: Codable, Sendable {
    public var snapshot: Snapshot?
    public var pending: [PendingCompletion]
    public init(snapshot: Snapshot? = nil, pending: [PendingCompletion] = []) { self.snapshot = snapshot; self.pending = pending }
}
public struct LocalCache: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> CachedState {
        guard FileManager.default.fileExists(atPath: url.path) else { return CachedState() }
        return try JSONDecoder().decode(CachedState.self, from: Data(contentsOf: url))
    }
    public func save(_ state: CachedState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var options: Data.WritingOptions = [.atomic]
        #if os(iOS)
        options.insert(.completeFileProtectionUntilFirstUserAuthentication)
        #endif
        try JSONEncoder().encode(state).write(to: url, options: options)
    }
}
