import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

struct RootView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Group {
            if store.account == nil { LoginView() }
            else {
                TabView(selection: $store.selectedTab) {
                    TodayView().tabItem { Label("Grove", systemImage: "tree.fill") }.tag(0)
                    PartnersView().tabItem { Label("Together", systemImage: "person.2.fill") }.tag(1)
                        .badge(store.state.snapshot?.nudges.filter { $0.recipient == store.me && $0.read == 0 }.count ?? 0)
                    ProgressTab().tabItem { Label("Progress", systemImage: "chart.bar.fill") }.tag(2)
                }
                .tint(.green)
                .overlay(alignment: .top) { LevelUpBanner() }
            }
        }
        .alert(store.error ?? "", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        }
        .sheet(isPresented: Binding(get: { store.focusedHabit != nil && store.state.snapshot != nil }, set: { if !$0 { store.focusedHabit = nil } })) {
            NavigationStack {
                HabitDetailView(id: store.focusedHabit ?? "")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { store.focusedHabit = nil } } }
            }
        }
    }
}

struct LoginView: View {
    @Environment(AppStore.self) private var store
    @State private var server = ""
    @State private var key = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server", text: $server, prompt: Text("https://habits.example.com"))
                        .textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Account key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: { Text("Use the key you received during setup. Your partner can see your habits and history.") }
                Section {
                    Button { Task { await store.login(server: server, key: key) } } label: {
                        HStack { Text("Sign in"); Spacer(); if store.busy { ProgressView() } }
                    }.disabled(server.isEmpty || key.isEmpty || store.busy)
                }
            }.navigationTitle("Two Together")
        }
    }
}

/// Quiet sync state. Shown only when something is waiting or failed.
struct SyncStatus: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        let count = store.state.pending.count
        if count > 0 || store.syncMessage != nil {
            HStack(spacing: 8) {
                Text(store.syncMessage ?? "\(count) check-in\(count == 1 ? "" : "s") waiting to sync")
                Spacer()
                Button("Retry") { Task { await store.sync() } }.disabled(store.busy)
            }.font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage("calmCards") private var calm = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(store.state.snapshot?.people ?? []) { person in LabeledContent(person.id == store.me ? "You" : "Partner", value: person.name) }
                    LabeledContent("Time zone", value: store.state.snapshot?.timezone ?? "America/Toronto")
                } footer: { Text("Your partner can see all your habits and history. Dates follow this time zone when you travel.") }
                Section {
                    Toggle("Calm cards", isOn: $calm)
                } footer: { Text("Keeps cards neutral and shows tree colors only in the trees, bars and day dots.") }
                Section {
                    #if PUSH_NOTIFICATIONS
                    Button("Turn on notifications") { Task { await store.enableNotifications() } }
                    Button("Open notification settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    #else
                    Text("Notifications need an Apple Developer Program team.")
                    #endif
                } header: { Text("Notifications") } footer: { Text("You’re notified only when your partner sends a nudge.") }
                Section {
                    Button("Sync now") { Task { await store.sync() } }.disabled(store.busy)
                } header: { Text("Sync") } footer: { Text(store.syncMessage ?? (store.busy ? "Syncing" : "Syncs every 15 seconds while the app is open.")) }
                Section { Button("Sign out", role: .destructive) { Task { await store.logout() } }.disabled(store.busy || !store.state.pending.isEmpty) }
            }
            .navigationTitle("Settings").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Celebrates a tree reaching a new stage, then gets out of the way.
struct LevelUpBanner: View {
    @Environment(AppStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            if let up = store.levelUp {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles").font(.title3.weight(.bold)).foregroundStyle(Palette.gold)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Level \(up.stage.rawValue + 1)!").font(.system(.headline, design: .rounded, weight: .heavy))
                        Text("\(up.name) grew into a \(up.stage.name.lowercased()).").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.color(up.color), lineWidth: 2))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 6)
                .padding(.top, 8)
                .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                .accessibilityElement(children: .combine)
                .onTapGesture { store.levelUp = nil }
                .task(id: up) {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation(.standard) { if store.levelUp == up { store.levelUp = nil } }
                }
            }
        }
        .animation(reduceMotion ? nil : .bouncy, value: store.levelUp)
        .sensoryFeedback(.levelChange, trigger: store.levelUp) { _, new in new != nil }
    }
}
