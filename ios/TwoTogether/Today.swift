import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

/// Your grove: one tree per habit, due ones first.
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
                VStack(alignment: .leading, spacing: 28) {
                    SyncStatus()
                    if habits.isEmpty {
                        ContentUnavailableView {
                            Label("Plant your first habit", systemImage: "leaf")
                        } description: { Text("Every habit grows a tree. Water it each day it’s due and watch it grow.") } actions: {
                            Button("Plant a habit") { creating = true }.buttonStyle(.borderedProminent).tint(.green)
                        }.padding(.top, 32)
                    } else {
                        TogetherBanner()
                        let scheduled = habits.filter { $0.isScheduled(store.today) }
                        let rest = habits.filter { !$0.isScheduled(store.today) }
                        if scheduled.isEmpty { Text("Nothing to water today.").foregroundStyle(.secondary) }
                        else { GroveGrid(habits: scheduled, zoom: zoom, editing: $editing) }
                        if !rest.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Resting today").font(.system(.title3, design: .rounded, weight: .bold))
                                GroveGrid(habits: rest, zoom: zoom, editing: $editing)
                            }
                        }
                    }
                }.padding(Metric.gutter)
            }
            .background(Palette.background)
            .navigationTitle("Grove")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Plant a habit", systemImage: "plus") { creating = true }
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
}

/// Two columns of tree tiles; one column at large text sizes.
struct GroveGrid: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let habits: [Habit]
    let zoom: Namespace.ID
    var editing: Binding<Habit?>?
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Metric.gutter), count: textSize >= .xxxLarge ? 1 : 2), spacing: 4) {
            ForEach(habits) { TreeTile(habit: $0, zoom: zoom, editing: editing) }
        }
    }
}

/// Today's watering for both of you, side by side.
struct TogetherBanner: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let people = [store.me] + (store.partner.map { [$0.id] } ?? [])
        let all = people.map { store.watered($0) }
        let bothDone = all.allSatisfy { $0.due > 0 && $0.done == $0.due }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(bothDone ? "Both groves watered" : "Watered today").font(.system(.headline, design: .rounded))
                Spacer()
                if bothDone { Image(systemName: "sparkles").foregroundStyle(Palette.gold).symbolEffect(.bounce, value: bothDone) }
            }
            ForEach(Array(zip(people, all)), id: \.0) { person, w in
                HStack(spacing: 10) {
                    Text(person == store.me ? "You" : store.name(person)).font(.subheadline.weight(.semibold)).frame(width: 72, alignment: .leading).lineLimit(1)
                    GrowthBar(progress: w.due == 0 ? 0 : Double(w.done) / Double(w.due), tint: person == store.me ? .green : .teal, track: Palette.fill, height: 10)
                    Text("\(w.done)/\(w.due)").font(.system(.subheadline, design: .rounded, weight: .semibold).monospacedDigit()).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(person == store.me ? "You" : store.name(person)): \(w.done) of \(w.due) watered")
            }
        }
        .padding(Metric.padding).padding(.bottom, Metric.lip)
        .background { CardBackground(habit: nil, tinted: false) }
    }
}
