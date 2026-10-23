import Foundation

/// Every habit is a tree. Check-ins grow it, unbroken runs grow it faster, and missed days dry it out.
public enum Stage: Int, CaseIterable, Comparable, Sendable {
    case seed, sprout, sapling, young, mature, grand, ancient
    public static func < (a: Stage, b: Stage) -> Bool { a.rawValue < b.rawValue }
    /// Growth points needed to reach this stage.
    public var threshold: Double { [0, 3, 10, 25, 50, 100, 200][rawValue] }
    public var next: Stage? { Stage(rawValue: rawValue + 1) }
    public var name: String { ["Seed", "Sprout", "Sapling", "Young tree", "Mature tree", "Grand tree", "Ancient tree"][rawValue] }
}

public struct Growth: Equatable, Sendable {
    /// Total growth. It never shrinks: misses cost vitality, not size.
    public var points: Double
    /// Share of the last 14 elapsed scheduled days that were done; 1 for a habit with no history yet.
    public var vitality: Double
    public var bestStreak: Int
    public var stage: Stage {
        Stage.allCases.last { points >= $0.threshold } ?? .seed
    }
    /// Progress from the current stage to the next, 0…1. Always 1 for an ancient tree.
    public var progress: Double {
        guard let next = stage.next else { return 1 }
        return min(1, (points - stage.threshold) / (next.threshold - stage.threshold))
    }
    /// Continuous size for rendering: whole stages plus progress through the current one.
    public var level: Double { Double(stage.rawValue) + (stage.next == nil ? 0 : progress) }
    public var wilting: Bool { vitality < 0.5 }
    public init(points: Double = 0, vitality: Double = 1, bestStreak: Int = 0) {
        self.points = points; self.vitality = vitality; self.bestStreak = bestStreak
    }
}

extension Tracking {
    /// Days window that decides how healthy a tree looks.
    public static let vitalityWindow = 14
    /// A check-in is worth 1 point, plus 1/7 for each prior day of the current run, capped at 3 points after two weeks.
    /// An open today counts neither for nor against.
    public static func growth(habit: Habit, today: String, isComplete: (String) -> Bool) -> Growth {
        guard var day = date(habit.start), let end = date(today) else { return Growth() }
        var points = 0.0, run = 0, best = 0
        var recent: [Bool] = []
        while day <= end {
            let k = key(day)
            if habit.isScheduled(k) {
                if isComplete(k) {
                    points += 1 + Double(min(run, 14)) / 7
                    run += 1; best = max(best, run)
                    recent.append(true)
                } else if k < today {
                    run = 0
                    recent.append(false)
                }
            }
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        let window = recent.suffix(vitalityWindow)
        let vitality = window.isEmpty ? 1 : Double(window.filter { $0 }.count) / Double(window.count)
        return Growth(points: points, vitality: vitality, bestStreak: best)
    }
}
