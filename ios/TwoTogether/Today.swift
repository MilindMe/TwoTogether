import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @Namespace private var zoom
    @State private var creating = false
    @State private var editing: Habit?
    @State private var settings = false
    private var habits: [Habit] {
        (store.state.snapshot?.habits ?? []).filter { $0.owner == store.me && ($0.archive.map { store.today < $0 } ?? true) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    SyncStatus()
                    if habits.isEmpty {
                        ContentUnavailableView {
                            Label("No habits yet", systemImage: "square.grid.2x2")
                        } description: { Text("Add one to get started.") } actions: {
                            Button("Add habit") { creating = true }.buttonStyle(.borderedProminent)
                        }.padding(.top, 32)
                    } else {
                        let scheduled = habits.filter { $0.isScheduled(store.today) }
                        let rest = habits.filter { !$0.isScheduled(store.today) }
                        if scheduled.isEmpty { Text("Nothing scheduled today.").foregroundStyle(.secondary) }
                        else { grid(scheduled) }
                        if !rest.isEmpty {
                            VStack(alignment: .leading, spacing: 24) {
                                Text("Not today").font(.title3.weight(.semibold))
                                grid(rest)
                            }
                        }
                    }
                }.padding(Metric.gutter)
            }
            .background(Palette.background)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Add habit", systemImage: "plus") { creating = true }
                    Button { settings = true } label: { Avatar(name: store.name(store.me)) }.accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: String.self) { HabitDetailView(id: $0).zoomDestination($0, in: zoom) }
            .refreshable { await store.sync() }
            .sheet(isPresented: $creating) { HabitEditor(habit: nil) }
            .sheet(item: $editing) { HabitEditor(habit: $0) }
            .sheet(isPresented: $settings) { SettingsView() }
        }
    }
    func grid(_ habits: [Habit]) -> some View {
        // At large text sizes small cards reflow to full width.
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Metric.gutter), count: textSize >= .xxxLarge ? 1 : 2), spacing: Metric.gutter) {
            ForEach(habits) { HabitTile(habit: $0, zoom: zoom, editing: $editing) }
        }
    }
}
