import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

/// A flat card with the habit's 3D tree growing out of its top edge.
/// The tree's mound sits inside the card; its canopy rises above it.
struct TreeCard: View {
    @Environment(AppStore.self) private var store
    @AppStorage("calmCards") private var calm = false
    let habit: Habit
    var body: some View {
        let scheduled = habit.isScheduled(store.today)
        let tinted = scheduled && !calm
        let ink = CardInk(habit: habit, tinted: tinted, paused: !scheduled)
        let growth = store.growth(habit)
        let streak = store.streak(habit)
        let mine = habit.owner == store.me
        let done = store.isComplete(habit.id, store.today)
        VStack(alignment: .leading, spacing: 6) {
            StageChip(growth: growth, ink: ink)
            Text(habit.name).font(.system(.headline, design: .rounded)).foregroundStyle(ink.primary).lineLimit(1)
            GrowthBar(progress: growth.progress, tint: tinted ? ink.primary : habit.accent, track: ink.track)
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").foregroundStyle(streak > 0 ? (tinted ? ink.primary : Palette.gold) : ink.secondary)
                Text(streak, format: .number).monospacedDigit().contentTransition(.numericText(value: Double(streak)))
                Spacer(minLength: 4)
                Text(!scheduled ? "Resting" : done ? (mine ? "Watered" : "Done") : "Due today").lineLimit(1)
            }
            .font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(ink.secondary)
        }
        .padding(.top, TreeTile.overlap)
        .padding(Metric.padding).padding(.bottom, Metric.lip)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background { CardBackground(habit: habit, tinted: tinted) }
        .padding(.top, TreeTile.treeHeight - TreeTile.overlap)
        .overlay(alignment: .top) {
            TreeView(spec: store.tree(habit)).frame(height: TreeTile.treeHeight).allowsHitTesting(false).accessibilityHidden(true)
        }
    }
}

/// A tree card that opens its detail. Your own trees carry a water button; your partner's carry a nudge.
struct TreeTile: View {
    /// Height of the 3D view, and how much of it overlaps the card. The mound lands inside the card.
    static let treeHeight: CGFloat = 180, overlap: CGFloat = 66
    @Environment(AppStore.self) private var store
    @AppStorage("calmCards") private var calm = false
    let habit: Habit
    let zoom: Namespace.ID
    var editing: Binding<Habit?>?
    var body: some View {
        let scheduled = habit.isScheduled(store.today)
        let done = store.isComplete(habit.id, store.today)
        let mine = habit.owner == store.me
        let ink = CardInk(habit: habit, tinted: scheduled && !calm, paused: !scheduled)
        let growth = store.growth(habit)
        NavigationLink(value: habit.id) { TreeCard(habit: habit) }
            .buttonStyle(CardPressStyle())
            .zoomSource(habit.id, in: zoom)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(habit.name), \(growth.stage.name)\(growth.wilting ? ", thirsty" : ""), \(scheduled ? (done ? "done today" : "not done today") : "rest day"), \(store.streak(habit))-day streak")
            .accessibilityAction(named: mine ? (done ? "Undo check-in" : "Water") : "Send nudge") {
                if mine { withAnimation(.standard) { store.toggle(habit, store.today) } }
                else if store.nudgeAllowed(habit) { Task { await store.mutate("nudge", ["habit": habit.id]) } }
            }
            .overlay(alignment: .topTrailing) {
                // Sits in the card's top corner, beside the tree's mound.
                Group {
                    if mine && scheduled { WaterButton(habit: habit, ink: ink) }
                    else if !mine && store.nudgeAllowed(habit) { NudgeButton(habit: habit, ink: ink) }
                }
                .padding(.top, Self.treeHeight - Self.overlap + Metric.padding - 6).padding(.trailing, Metric.padding - 6)
            }
            .contextMenu {
                if mine && scheduled {
                    Button(done ? "Undo check-in" : "Water", systemImage: done ? "arrow.uturn.backward" : "drop.fill") { withAnimation(.standard) { store.toggle(habit, store.today) } }
                }
                if let editing, mine { Button("Edit habit", systemImage: "pencil") { editing.wrappedValue = habit } }
            }
    }
}

struct NudgeButton: View {
    @Environment(AppStore.self) private var store
    let habit: Habit
    let ink: CardInk
    var body: some View {
        Button { Task { await store.mutate("nudge", ["habit": habit.id]) } } label: {
            Image(systemName: "hand.wave.fill").font(.system(size: 16, weight: .bold)).foregroundStyle(ink.mark)
                .frame(width: 40, height: 40).background(ink.track, in: Circle())
                .frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(store.busy)
        .accessibilityHidden(true)
    }
}

/// Medium card: one habit's week, with its tree's stage.
struct WeekCard: View {
    @Environment(AppStore.self) private var store
    @AppStorage("calmCards") private var calm = false
    let habit: Habit
    let dates: [String]
    var body: some View {
        let ink = CardInk(habit: habit, tinted: !calm)
        let t = Tracking.totals(habit: habit, dates: dates, today: store.today) { store.isComplete(habit.id, $0) }
        let growth = store.growth(habit)
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                StageChip(growth: growth, ink: ink)
                Spacer()
                Text("\(t.done)/\(t.elapsed)").font(.system(.title3, design: .rounded, weight: .semibold).monospacedDigit())
                    .foregroundStyle(ink.primary)
            }
            Spacer(minLength: 12)
            Text(habit.name).font(.system(.headline, design: .rounded)).foregroundStyle(ink.primary).lineLimit(2)
            GrowthBar(progress: growth.progress, tint: calm ? habit.accent : ink.primary, track: ink.track, height: 6).padding(.top, 8)
            SevenDayStrip(habit: habit, dates: dates, ink: ink).padding(.top, 10)
        }
        .padding(Metric.padding).padding(.bottom, Metric.lip)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .background { CardBackground(habit: habit, tinted: !calm) }
    }
}

/// Keeps widget proportions: 364 × 170 for medium cards.
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
