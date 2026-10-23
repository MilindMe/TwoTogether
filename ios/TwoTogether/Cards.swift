import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

/// Small widget card: glyph and ring on top, streak, name and week total anchored bottom-left.
struct HabitCard: View {
    @Environment(AppStore.self) private var store
    @AppStorage("calmCards") private var calm = false
    let habit: Habit
    var body: some View {
        let scheduled = habit.isScheduled(store.today)
        let tinted = scheduled && !calm
        let ink = CardInk(habit: habit, tinted: tinted, paused: !scheduled)
        let streak = store.streak(habit)
        let week = store.week(habit)
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: habit.icon).font(.title3).foregroundStyle(ink.glyph)
                .symbolRenderingMode(tinted ? .monochrome : .hierarchical)
                .frame(height: 28)
            Spacer(minLength: 8)
            Text(streak, format: .number).font(.system(.largeTitle, design: .rounded, weight: .bold).monospacedDigit())
                .contentTransition(.numericText(value: Double(streak)))
                .foregroundStyle(ink.primary)
            Text(habit.name).font(.headline).foregroundStyle(ink.primary).lineLimit(1).padding(.top, 4)
            Text(scheduled ? "\(week.done) of \(week.elapsed) this week" : "Rest day")
                .font(.subheadline).foregroundStyle(ink.secondary).lineLimit(1).padding(.top, 4)
        }
        .padding(Metric.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background { CardBackground(habit: habit, tinted: tinted) }
    }
}

/// A small card that opens its detail, with the check-off ring as its own tap target.
struct HabitTile: View {
    @Environment(AppStore.self) private var store
    @AppStorage("calmCards") private var calm = false
    let habit: Habit
    let zoom: Namespace.ID
    @Binding var editing: Habit?
    var body: some View {
        let scheduled = habit.isScheduled(store.today)
        let done = store.isComplete(habit.id, store.today)
        NavigationLink(value: habit.id) { HabitCard(habit: habit).widget() }
            .buttonStyle(CardPressStyle())
            .zoomSource(habit.id, in: zoom)
            .accessibilityLabel("\(habit.name), \(scheduled ? (done ? "done today" : "not done today") : "rest day"), \(store.streak(habit))-day streak")
            .accessibilityAction(named: done ? "Undo check-in" : "Check off") { withAnimation(.standard) { store.toggle(habit, store.today) } }
            .overlay(alignment: .topTrailing) {
                // The ring keeps a 44 pt target while sitting on the card's 16 pt padding.
                if scheduled { CheckRing(habit: habit, ink: CardInk(habit: habit, tinted: !calm)).padding(Metric.padding - 8) }
            }
            .contextMenu {
                if scheduled {
                    Button(done ? "Undo check-in" : "Check off", systemImage: done ? "arrow.uturn.backward" : "checkmark") { withAnimation(.standard) { store.toggle(habit, store.today) } }
                }
                Button("Edit habit", systemImage: "pencil") { editing = habit }
            }
    }
}

/// Medium widget card: one habit with its seven-day strip.
struct WeekCard: View {
    @Environment(AppStore.self) private var store
    @AppStorage("calmCards") private var calm = false
    let habit: Habit
    let dates: [String]
    var body: some View {
        let ink = CardInk(habit: habit, tinted: !calm)
        let t = Tracking.totals(habit: habit, dates: dates, today: store.today) { store.isComplete(habit.id, $0) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: habit.icon).font(.title3).foregroundStyle(ink.glyph)
                    .symbolRenderingMode(calm ? .hierarchical : .monochrome)
                Spacer()
                Text("\(t.done)/\(t.elapsed)").font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ink.primary)
            }
            Spacer(minLength: 16)
            Text(habit.name).font(.headline).foregroundStyle(ink.primary).lineLimit(2)
            SevenDayStrip(habit: habit, dates: dates, ink: ink).padding(.top, 8)
        }
        .padding(Metric.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background { CardBackground(habit: habit, tinted: !calm) }
    }
}

/// Keeps widget proportions: a square for small cards, 364 × 170 for medium.
/// At large text sizes cards reflow to full width and grow to fit their content.
struct WidgetFrame: ViewModifier {
    @Environment(\.dynamicTypeSize) private var textSize
    let ratio: CGFloat
    func body(content: Content) -> some View {
        if textSize >= .xxxLarge { content.frame(minHeight: 170) }
        else { Color.clear.aspectRatio(ratio, contentMode: .fit).overlay { content } }
    }
}
extension View {
    func widget(_ ratio: CGFloat = 1) -> some View { modifier(WidgetFrame(ratio: ratio)) }
}
