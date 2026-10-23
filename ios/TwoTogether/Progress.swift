import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

struct ProgressTab: View {
    @Environment(AppStore.self) private var store
    @Namespace private var zoom
    @State private var partner = false
    @State private var offset = 0
    private var dates: [String] { Tracking.week(containing: store.today, offset: offset) }
    private var habits: [Habit] {
        let owner = partner ? store.partner?.id : store.me
        return (store.state.snapshot?.habits ?? []).filter { h in h.owner == owner && h.start <= dates[6] && (h.archive.map { $0 > dates[0] } ?? true) }
    }
    var body: some View {
        let totals = habits.reduce((done: 0, elapsed: 0)) { sum, h in
            let t = Tracking.totals(habit: h, dates: dates, today: store.today) { store.isComplete(h.id, $0) }
            return (sum.done + t.done, sum.elapsed + t.elapsed)
        }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Picker("Person", selection: $partner) {
                        Text("You").tag(false)
                        Text(store.partner?.name ?? "Partner").tag(true)
                    }.pickerStyle(.segmented)
                    SyncStatus()
                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(Format.day(dates[0])) – \(Format.day(dates[6]))").font(.title3.weight(.semibold))
                            Text("\(totals.done) of \(totals.elapsed) check-ins done").font(.subheadline).foregroundStyle(.secondary)
                        }.accessibilityElement(children: .combine)
                        Spacer()
                        Button("Previous week", systemImage: "chevron.left") { offset -= 1 }.labelStyle(.iconOnly).frame(width: 44, height: 44)
                        Button("Next week", systemImage: "chevron.right") { offset += 1 }.labelStyle(.iconOnly).frame(width: 44, height: 44).disabled(offset >= 0)
                    }
                    if habits.isEmpty { Text("No habits this week.").foregroundStyle(.secondary) }
                    else {
                        LazyVStack(spacing: Metric.gutter) {
                            ForEach(habits) { h in
                                NavigationLink(value: h.id) { WeekCard(habit: h, dates: dates).widget(364 / 170) }
                                    .buttonStyle(CardPressStyle())
                                    .zoomSource(h.id, in: zoom)
                                    .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }.padding(Metric.gutter)
            }
            .background(Palette.background)
            .navigationTitle("Progress")
            .navigationDestination(for: String.self) { HabitDetailView(id: $0).zoomDestination($0, in: zoom) }
            .refreshable { await store.sync() }
        }
    }
}
