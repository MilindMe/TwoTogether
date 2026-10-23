import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

/// Your partner's grove, read-only with nudges, and the nudges you've received.
struct PartnersView: View {
    @Environment(AppStore.self) private var store
    @Namespace private var zoom
    private var inbox: [Nudge] { store.state.snapshot?.nudges.filter { $0.recipient == store.me } ?? [] }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    SyncStatus()
                    if let partner = store.partner {
                        let habits = (store.state.snapshot?.habits ?? []).filter { $0.owner == partner.id && $0.isScheduled(store.today) }
                        let w = store.watered(partner.id)
                        HStack(spacing: 12) {
                            Avatar(name: partner.name)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(partner.name)’s grove").font(.system(.headline, design: .rounded))
                                Text(store.lastCheckIn(partner.id).map { "Watered \(Format.relative($0))" } ?? "Nothing watered yet")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(w.done)/\(w.due)").font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit())
                        }
                        .padding(Metric.padding).padding(.bottom, Metric.lip)
                        .background { CardBackground(habit: nil, tinted: false) }
                        .accessibilityElement(children: .combine)
                        if habits.isEmpty { Text("Nothing due today.").foregroundStyle(.secondary) }
                        else { GroveGrid(habits: habits, zoom: zoom) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nudges").font(.system(.title3, design: .rounded, weight: .bold))
                        VStack(spacing: 0) {
                            if inbox.isEmpty { Text("No nudges yet.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(Metric.padding) }
                            ForEach(inbox) { n in
                                Button { Task { await store.openNudge(habit: n.habit, nudge: n.id) } } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                                        Circle().fill(.tint).frame(width: 8, height: 8).opacity(n.read == 0 ? 1 : 0)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("\(store.name(n.sender)) nudged you about \(store.state.snapshot?.habits.first { $0.id == n.habit }?.name ?? "a habit").")
                                                .foregroundStyle(Color.primary).multilineTextAlignment(.leading)
                                            Text(AppStore.instant(n.created_at).map(Format.relative) ?? Format.day(n.date)).font(.footnote).foregroundStyle(Color.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }.padding(Metric.padding).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityElement(children: .combine).accessibilityValue(n.read == 0 ? "Unread" : "")
                                if n.id != inbox.last?.id { Divider().padding(.leading, Metric.padding + 20) }
                            }
                        }
                        .padding(.bottom, Metric.lip)
                        .background { CardBackground(habit: nil, tinted: false) }
                        Text("Nudges stay here even when notifications are off. You can send one per habit and three a day.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(Metric.gutter)
            }
            .background(Palette.background)
            .navigationTitle("Together")
            .navigationDestination(for: String.self) { HabitDetailView(id: $0).zoomDestination($0, in: zoom) }
            .refreshable { await store.sync() }
        }
    }
}
