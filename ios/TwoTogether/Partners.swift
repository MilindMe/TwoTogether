import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

struct PartnersView: View {
    @Environment(AppStore.self) private var store
    @Namespace private var zoom
    private var inbox: [Nudge] { store.state.snapshot?.nudges.filter { $0.recipient == store.me } ?? [] }
    var body: some View {
        NavigationStack {
            List {
                if let partner = store.partner {
                    let habits = (store.state.snapshot?.habits ?? []).filter { $0.owner == partner.id && $0.isScheduled(store.today) }
                    Section {
                        HStack(spacing: 12) {
                            Avatar(name: partner.name)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(partner.name)
                                Text(store.lastCheckIn(partner.id).map { "Checked in \(Format.relative($0))" } ?? "No check-ins yet")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }.accessibilityElement(children: .combine)
                    }
                    Section("Today") {
                        if habits.isEmpty { Text("Nothing scheduled today.").foregroundStyle(.secondary) }
                        ForEach(habits) { h in
                            NavigationLink(value: h.id) { PartnerHabitRow(habit: h) }.zoomSource(h.id, in: zoom)
                        }
                    }
                }
                Section {
                    if inbox.isEmpty { Text("No nudges yet.").foregroundStyle(.secondary) }
                    ForEach(inbox) { n in
                        Button { Task { await store.openNudge(habit: n.habit, nudge: n.id) } } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Circle().fill(.tint).frame(width: 8, height: 8).opacity(n.read == 0 ? 1 : 0)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(store.name(n.sender)) nudged you about \(store.state.snapshot?.habits.first { $0.id == n.habit }?.name ?? "a habit").")
                                        .foregroundStyle(Color.primary)
                                    Text(AppStore.instant(n.created_at).map(Format.relative) ?? Format.day(n.date)).font(.footnote).foregroundStyle(Color.secondary)
                                }
                            }
                        }.accessibilityElement(children: .combine).accessibilityValue(n.read == 0 ? "Unread" : "")
                    }
                } header: { Text("Nudges") } footer: { Text("Nudges stay here even when notifications are off.") }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Partners")
            .navigationDestination(for: String.self) { HabitDetailView(id: $0).zoomDestination($0, in: zoom) }
            .refreshable { await store.sync() }
        }
    }
}

struct PartnerHabitRow: View {
    @Environment(AppStore.self) private var store
    let habit: Habit
    var body: some View {
        let done = store.isComplete(habit.id, store.today)
        HStack(spacing: 12) {
            Image(systemName: habit.icon).font(.title3).symbolRenderingMode(.hierarchical).foregroundStyle(habit.accent).frame(width: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name).lineLimit(2)
                Text(done ? "Done" : store.nudgeSent(habit) ? "Nudge sent" : "Not yet").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if done { Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(habit.accent).accessibilityHidden(true) }
            else if store.nudgeAllowed(habit) {
                Button("Send nudge") { Task { await store.mutate("nudge", ["habit": habit.id]) } }
                    .buttonStyle(.bordered).controlSize(.small).disabled(store.busy)
            }
        }
    }
}
