import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

// Tokens and shared components. Change them here, not in screens.
enum Palette {
    static let names = ["red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink"]
    static func color(_ name: String) -> Color {
        switch name {
        case "red": .red; case "orange": .orange; case "yellow": .yellow; case "mint": .mint; case "teal": .teal
        case "blue": .blue; case "indigo": .indigo; case "purple": .purple; case "pink": .pink; default: .green
        }
    }
    /// Each colour grows a different kind of tree.
    static func species(_ name: String) -> String {
        ["red": "Maple", "orange": "Beech", "yellow": "Ginkgo", "green": "Oak", "mint": "Willow", "teal": "Cedar",
         "blue": "Moonwood", "indigo": "Starbark", "purple": "Jacaranda", "pink": "Cherry blossom"][name] ?? "Oak"
    }
    /// Meadow light by day, a deep forest at night.
    static let skyTop = dynamic(light: (0.89, 0.95, 0.87), dark: (0.06, 0.13, 0.11))
    static let skyBottom = dynamic(light: (0.98, 0.96, 0.9), dark: (0.04, 0.07, 0.06))
    static let surface = dynamic(light: (1, 1, 0.98), dark: (0.11, 0.17, 0.15))
    static let fill = Color(.secondarySystemFill)
    static let gold = Color(red: 0.98, green: 0.72, blue: 0.16)
    static var background: some View {
        LinearGradient(colors: [skyTop, skyBottom], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
}
extension Habit {
    var accent: Color { Palette.color(color) }
    // Yellow and Mint fills take black text for contrast; every other fill takes white.
    var onAccent: Color { ["yellow", "mint"].contains(color) ? .black.opacity(0.85) : .white }
}
extension Animation {
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let bouncy = Animation.spring(response: 0.45, dampingFraction: 0.6)
}
enum Metric {
    static let radius: CGFloat = 24, padding: CGFloat = 14, gutter: CGFloat = 14
    /// The darker band under each card that makes it read as a chunky game tile.
    static let lip: CGFloat = 5
}

/// Foreground colours for content on a card, tinted or neutral.
struct CardInk {
    let primary: Color, secondary: Color, track: Color, glyph: Color, mark: Color
    init(habit: Habit, tinted: Bool, paused: Bool = false) {
        if tinted {
            primary = habit.onAccent; secondary = habit.onAccent.opacity(0.75); track = habit.onAccent.opacity(0.25)
            glyph = habit.onAccent; mark = habit.onAccent
        } else {
            primary = .primary; secondary = .secondary; track = Palette.fill
            glyph = paused ? Color(.tertiaryLabel) : habit.accent; mark = habit.accent
        }
    }
}
/// A flat card with a darker lip along its bottom edge.
struct CardBackground: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let habit: Habit?
    let tinted: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
        let base: Color = tinted ? (habit?.accent ?? Palette.surface) : Palette.surface
        ZStack {
            shape.fill(base).overlay(shape.fill(.black.opacity(tinted ? 0.22 : 0.08)))
            shape.fill(base).padding(.bottom, Metric.lip)
                .overlay { if contrast == .increased && tinted { shape.fill(.black.opacity(0.15)).padding(.bottom, Metric.lip) } }
        }
    }
}
struct CardPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(.standard, value: configuration.isPressed)
    }
}

/// The check-off: water today's tree. The drop fills, a success haptic plays, and the tree grows.
struct WaterButton: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let habit: Habit
    let ink: CardInk
    var diameter: CGFloat = 40
    @State private var success = 0
    var body: some View {
        let done = store.isComplete(habit.id, store.today)
        let enabled = store.canCorrect(habit, store.today)
        Button {
            if !done { success += 1 }
            withAnimation(reduceMotion ? nil : .bouncy) { store.toggle(habit, store.today) }
        } label: {
            ZStack {
                Circle().fill(done ? ink.mark : ink.track)
                Circle().strokeBorder(ink.mark.opacity(done ? 0 : 0.6), lineWidth: 2)
                Image(systemName: done ? "checkmark" : "drop.fill")
                    .font(.system(size: diameter * 0.42, weight: .bold))
                    .foregroundStyle(done ? (ink.mark == .white ? habit.accent : .white) : ink.mark)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(done && !reduceMotion ? 1.06 : 1)
            .frame(width: max(diameter, 44), height: max(diameter, 44)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .sensoryFeedback(.success, trigger: success)
        .accessibilityHidden(true)
    }
}

/// Progress through the current stage toward the next.
struct GrowthBar: View {
    let progress: Double
    let tint: Color
    let track: Color
    var height: CGFloat = 8
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint).frame(width: max(height, geo.size.width * progress))
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

/// "Lv 3 · Young tree" with a wilting warning when the tree is dry.
struct StageChip: View {
    let growth: Growth
    let ink: CardInk
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: growth.wilting ? "drop.triangle.fill" : "leaf.fill").imageScale(.small)
            Text(growth.wilting ? "Thirsty" : "Lv \(growth.stage.rawValue + 1) · \(growth.stage.name)").lineLimit(1)
        }
        .font(.caption.weight(.semibold)).foregroundStyle(ink.primary)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(ink.track, in: Capsule())
    }
}

struct SevenDayStrip: View {
    @Environment(AppStore.self) private var store
    let habit: Habit
    let dates: [String]
    let ink: CardInk
    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(dates.enumerated()), id: \.offset) { i, date in
                let state = Tracking.state(habit: habit, date: date, today: store.today, completed: store.isComplete(habit.id, date))
                VStack(spacing: 4) {
                    Group {
                        switch state {
                        case .completed: Circle().fill(ink.mark)
                        case .missed, .open: Circle().strokeBorder(ink.secondary, lineWidth: 1.5)
                        case .upcoming, .unscheduled: Circle().fill(ink.track)
                        }
                    }.frame(width: 10, height: 10)
                    Text(["M", "T", "W", "T", "F", "S", "S"][i]).font(.caption.weight(date == store.today ? .semibold : .medium))
                        .foregroundStyle(date == store.today ? ink.primary : ink.secondary)
                }.frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(dates.map { date in
            let state = Tracking.state(habit: habit, date: date, today: store.today, completed: store.isComplete(habit.id, date))
            return "\(Format.weekday(date)) \(Format.cell(state))"
        }.joined(separator: ", "))
    }
}

struct Avatar: View {
    let name: String
    var body: some View {
        Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased())
            .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            .frame(width: 32, height: 32).background(Palette.fill, in: Circle())
            .accessibilityHidden(true)
    }
}

enum Format {
    static func weekday(_ key: String) -> String {
        guard let d = Tracking.date(key) else { return key }
        return d.formatted(Date.FormatStyle(timeZone: TimeZone(secondsFromGMT: 0)!).weekday(.wide))
    }
    static func day(_ key: String) -> String {
        guard let d = Tracking.date(key) else { return key }
        return d.formatted(Date.FormatStyle(timeZone: TimeZone(secondsFromGMT: 0)!).month(.abbreviated).day())
    }
    static func cell(_ state: CellState) -> String {
        switch state { case .completed: "done"; case .missed: "missed"; case .open: "not done yet"; case .upcoming: "upcoming"; case .unscheduled: "rest day" }
    }
    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }
}

// Zoom from a card into its detail on iOS 18; the standard push elsewhere.
extension View {
    @ViewBuilder func zoomSource(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) { matchedTransitionSource(id: id, in: namespace) } else { self }
    }
    @ViewBuilder func zoomDestination(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18, *) { navigationTransition(.zoom(sourceID: id, in: namespace)) } else { self }
    }
}
