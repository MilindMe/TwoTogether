import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

// Tokens and shared components from DESIGN.md. Change them here, not in screens.
enum Palette {
    static let names = ["red", "orange", "yellow", "green", "mint", "teal", "blue", "indigo", "purple", "pink"]
    static func color(_ name: String) -> Color {
        switch name {
        case "red": .red; case "orange": .orange; case "yellow": .yellow; case "mint": .mint; case "teal": .teal
        case "blue": .blue; case "indigo": .indigo; case "purple": .purple; case "pink": .pink; default: .green
        }
    }
    static let background = Color(.systemGroupedBackground)
    static let surface = Color(.secondarySystemGroupedBackground)
    static let fill = Color(.secondarySystemFill)
}
extension Habit {
    var accent: Color { Palette.color(color) }
    // Yellow and Mint fills take black text for contrast; every other fill takes white.
    var onAccent: Color { ["yellow", "mint"].contains(color) ? .black.opacity(0.85) : .white }
}
extension Animation {
    static let standard = Animation.spring(response: 0.35, dampingFraction: 0.85)
}
enum Metric {
    static let radius: CGFloat = 22, padding: CGFloat = 16, gutter: CGFloat = 16
}

/// Foreground colours for content on a card, tinted or neutral.
struct CardInk {
    let primary: Color, secondary: Color, track: Color, glyph: Color, mark: Color
    init(habit: Habit, tinted: Bool, paused: Bool = false) {
        if tinted {
            primary = habit.onAccent; secondary = habit.onAccent.opacity(0.7); track = habit.onAccent.opacity(0.25)
            glyph = habit.onAccent; mark = habit.onAccent
        } else {
            primary = .primary; secondary = .secondary; track = Palette.fill
            glyph = paused ? Color(.tertiaryLabel) : habit.accent; mark = habit.accent
        }
    }
}
struct CardBackground: View {
    @Environment(\.colorSchemeContrast) private var contrast
    let habit: Habit?
    let tinted: Bool
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metric.radius, style: .continuous)
        if tinted, let habit {
            // Increase Contrast drops the gradient and darkens the fill one step.
            if contrast == .increased { shape.fill(habit.accent).overlay(shape.fill(.black.opacity(0.15))) }
            // Top is the same hue about 6% lighter; the shift should be barely visible.
            else { shape.fill(habit.accent).overlay(shape.fill(LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom))) }
        } else { shape.fill(Palette.surface) }
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

struct ProgressRing: View {
    let progress: Double
    let tint: Color
    let track: Color
    let diameter: CGFloat
    var body: some View {
        let width = diameter * 0.12
        ZStack {
            Circle().inset(by: width / 2).stroke(track, lineWidth: width)
            Circle().inset(by: width / 2).trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: width, lineCap: .round)).rotationEffect(.degrees(-90))
        }.frame(width: diameter, height: diameter)
    }
}

/// The check-off moment: the ring fills, cross-fades to a checkmark, and a success haptic plays.
struct CheckRing: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let habit: Habit
    let ink: CardInk
    var diameter: CGFloat = 28
    @State private var filled = false
    @State private var checked = false
    @State private var success = 0
    var body: some View {
        let done = store.isComplete(habit.id, store.today)
        let enabled = store.canCorrect(habit, store.today)
        Button {
            if !done { success += 1 }
            withAnimation(reduceMotion ? nil : .standard) { store.toggle(habit, store.today) }
        } label: {
            ZStack {
                if checked {
                    Image(systemName: "checkmark.circle.fill").resizable().scaledToFit()
                        .foregroundStyle(ink.mark).transition(.opacity)
                } else {
                    ProgressRing(progress: filled ? 1 : 0, tint: ink.mark, track: ink.track, diameter: diameter).transition(.opacity)
                }
            }.frame(width: diameter, height: diameter).frame(width: max(diameter, 44), height: max(diameter, 44)).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
        .sensoryFeedback(.success, trigger: success)
        .onAppear { filled = done; checked = done }
        .onChange(of: done) { _, now in
            if !now { withAnimation(.standard) { checked = false; filled = false }; return }
            if reduceMotion { withAnimation(.easeOut(duration: 0.2)) { filled = true; checked = true }; return }
            withAnimation(.standard) { filled = true }
            Task { try? await Task.sleep(for: .seconds(0.4)); withAnimation(.standard) { checked = store.isComplete(habit.id, store.today) } }
        }
        .accessibilityHidden(true)
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
