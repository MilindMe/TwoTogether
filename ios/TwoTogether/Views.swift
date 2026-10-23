import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

extension Habit {
    var accent: Color { switch color { case "blue": .blue; case "purple": .purple; case "orange": .orange; case "pink": .pink; case "teal": .teal; default: .green } }
}
struct RootView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        @Bindable var store = store
        Group {
            if store.account == nil { LoginView() }
            else {
                TabView(selection: $store.selectedTab) {
                    TodayView().tabItem { Label("Today", systemImage: "square.grid.2x2.fill") }.tag(0)
                    WeekView().tabItem { Label("Week", systemImage: "calendar") }.tag(1)
                    InboxView().tabItem { Label("Nudges", systemImage: "hand.wave.fill") }.tag(2)
                        .badge(store.state.snapshot?.nudges.filter { $0.recipient == store.me && $0.read == 0 }.count ?? 0)
                    SettingsView().tabItem { Label("Settings", systemImage: "gearshape") }.tag(3)
                }
            }
        }
        .alert("A quick update", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .sheet(isPresented: Binding(get: { store.focusedHabit != nil && store.state.snapshot != nil }, set: { if !$0 { store.focusedHabit = nil } })) {
            if let h = store.state.snapshot?.habits.first(where: { $0.id == store.focusedHabit }) { HabitFocusView(habit: h) }
            else { ContentUnavailableView("Habit unavailable", systemImage: "leaf") }
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
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: "leaf.circle.fill").font(.system(size: 54)).foregroundStyle(.indigo)
                        Text("Small steps.\nShared momentum.").font(.largeTitle.bold())
                        Text("A private space for you and your accountability partner.").foregroundStyle(.secondary)
                    }.padding(.vertical, 20)
                }.listRowBackground(Color.clear)
                Section {
                    TextField("Server address · https://…", text: $server).textContentType(.URL).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Your provisioned account key", text: $key).textInputAutocapitalization(.never).autocorrectionDisabled()
                } header: { Text("Your private account") } footer: { Text("Use the account key supplied during setup. Your habits and complete history are visible to your partner. There is no public registration.") }
                Section {
                    Button { Task { await store.login(server: server, key: key) } } label: {
                        HStack { Text("Let’s begin").bold(); Spacer(); if store.busy { ProgressView() } else { Image(systemName: "arrow.right") } }
                    }.disabled(server.isEmpty || key.isEmpty || store.busy)
                }
            }.navigationTitle("Two Together")
        }
    }
}
struct PersonPicker: View {
    @Environment(AppStore.self) private var store
    @Binding var partner: Bool
    var body: some View {
        Picker("Whose habits", selection: $partner) {
            Text("My Habits").tag(false)
            Text(store.partner.map { "\($0.name)’s Habits" } ?? "Partner’s Habits").tag(true)
        }.pickerStyle(.segmented)
    }
}
struct SyncBanner: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        if !store.state.pending.isEmpty || store.syncMessage != nil {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                Text(store.state.pending.isEmpty ? "Offline · showing your last synced progress" : "\(store.state.pending.count) check-in\(store.state.pending.count == 1 ? "" : "s") saved · waiting to sync").font(.caption)
                Spacer()
                Button("Retry") { Task { await store.sync() } }.disabled(store.busy)
            }.padding(12).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)).accessibilityElement(children: .combine)
        }
    }
}
struct TodayView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dynamicTypeSize) private var textSize
    @State private var partner = false
    @State private var creating = false
    @State private var editing: Habit?
    private var habits: [Habit] {
        let owner = partner ? store.partner?.id : store.me
        return (store.state.snapshot?.habits ?? []).filter { $0.owner == owner && ($0.archive.map { store.today < $0 } ?? true) }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PersonPicker(partner: $partner)
                    SyncBanner()
                    let scheduled = habits.filter { $0.isScheduled(store.today) }
                    let done = scheduled.filter { store.isComplete($0.id, store.today) }.count
                    VStack(alignment: .leading, spacing: 8) {
                        Text(partner ? "A little encouragement goes a long way." : "Make room for a small win.").font(.title2.bold())
                        Text("\(done) of \(scheduled.count) completed").foregroundStyle(.secondary)
                        ProgressView(value: Double(done), total: Double(max(scheduled.count, 1))).tint(.indigo).accessibilityLabel("Daily progress")
                    }
                    if habits.isEmpty {
                        ContentUnavailableView {
                            Label(partner ? "A fresh start" : "Your first small step", systemImage: "leaf")
                        } description: {
                            Text(partner ? "Your partner’s habits will appear here once they create one." : "Choose something you’d like to show up for today.")
                        } actions: { if !partner { Button("Create a habit") { creating = true }.buttonStyle(.borderedProminent) } }
                    } else {
                        if scheduled.isEmpty { Text("A little breathing room. No habits scheduled today.").foregroundStyle(.secondary) }
                        grid(scheduled, scheduled: true)
                        let off = habits.filter { !$0.isScheduled(store.today) }
                        if !off.isEmpty {
                            Text("Not scheduled today").font(.headline).foregroundStyle(.secondary)
                            grid(off, scheduled: false)
                        }
                    }
                    Text("\(store.today) · \(store.state.snapshot?.timezone ?? "America/Toronto")").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Color(.systemGroupedBackground))
                .navigationTitle("Today")
                .toolbar { if !partner { Button("Add habit", systemImage: "plus") { creating = true } } }
                .refreshable { await store.sync() }
                .sheet(isPresented: $creating) { HabitEditor(habit: nil) }
                .sheet(item: $editing) { HabitEditor(habit: $0) }
        }
    }
    func grid(_ habits: [Habit], scheduled: Bool) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: textSize.isAccessibilitySize ? 1 : 2), spacing: 14) {
            ForEach(habits) { h in
                VStack(alignment: .leading, spacing: 10) {
                    Button { store.toggle(h, store.today) } label: { HabitCard(habit: h, scheduled: scheduled) }
                        .buttonStyle(.plain).disabled(partner || !scheduled)
                        .accessibilityLabel("\(h.name), \(scheduled ? (store.isComplete(h.id, store.today) ? "completed" : "incomplete") : "not scheduled today")")
                        .accessibilityHint(partner ? "Your partner’s progress" : "Double tap to change today’s completion")
                    if partner && scheduled {
                        Button { Task { _ = await store.mutate("nudge", ["habit": h.id]) } } label: { Label("Send a nudge", systemImage: "hand.wave") }.font(.caption.bold()).disabled(!store.nudgeAllowed(h) || store.busy)
                    } else if !partner {
                        Button("Edit habit") { editing = h }.font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
struct HabitCard: View {
    @Environment(AppStore.self) private var store
    let habit: Habit
    let scheduled: Bool
    var body: some View {
        let done = store.isComplete(habit.id, store.today)
        let pending = store.state.pending.contains { $0.habit == habit.id && $0.date == store.today }
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: habit.icon).font(.title2).foregroundStyle(habit.accent)
                Spacer()
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.title2).foregroundStyle(done ? habit.accent : Color.secondary)
            }
            Text(habit.name).font(.headline).foregroundStyle(.primary).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
            Label(pending ? "Pending sync" : !scheduled ? "Rest day" : done ? "Done for today" : "Ready when you are", systemImage: pending ? "arrow.triangle.2.circlepath" : !scheduled ? "moon" : done ? "checkmark" : "sparkle")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(scheduled ? habit.accent.opacity(done ? 0.20 : 0.08) : Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(done ? habit.accent.opacity(0.5) : .clear, lineWidth: 2))
            .opacity(scheduled ? 1 : 0.6)
    }
}
struct HabitEditor: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let habit: Habit?
    @State private var name: String
    @State private var icon: String
    @State private var color: String
    @State private var weekdays: Set<Int>
    @State private var confirmArchive = false
    @State private var newID = UUID().uuidString
    private let icons = ["leaf.fill", "figure.walk", "book.fill", "drop.fill", "moon.fill", "heart.fill", "sun.max.fill", "dumbbell.fill"]
    private let colors = ["green", "blue", "purple", "orange", "pink", "teal"]
    init(habit: Habit?) {
        self.habit = habit
        _name = State(initialValue: habit?.name ?? "")
        _icon = State(initialValue: habit?.icon ?? "leaf.fill")
        _color = State(initialValue: habit?.color ?? "green")
        _weekdays = State(initialValue: Set(habit?.schedules.last?.weekdays ?? Array(1...7)))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("A small commitment") { TextField("Habit name", text: $name).onChange(of: name) { _, value in name = String(value.prefix(60)) } }
                Section("Make it yours") {
                    Picker("Icon", selection: $icon) { ForEach(icons, id: \.self) { Image(systemName: $0).accessibilityLabel($0.replacingOccurrences(of: ".fill", with: "")).tag($0) } }
                    Picker("Accent", selection: $color) { ForEach(colors, id: \.self) { Text($0.capitalized).tag($0) } }
                }
                Section {
                    Toggle("Every day", isOn: Binding(get: { weekdays.count == 7 }, set: { weekdays = $0 ? Set(1...7) : [] }))
                    ForEach(1...7, id: \.self) { day in
                        Toggle(["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"][day - 1], isOn: Binding(get: { weekdays.contains(day) }, set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } }))
                    }
                } header: { Text("Schedule") } footer: { Text(habit == nil ? "Your habit starts today. Previous days won’t count as missed." : "Schedule changes begin tomorrow. Past weeks keep their original schedule.") }
                if let h = habit {
                    Section {
                        Button("Archive habit", role: .destructive) { confirmArchive = true }.disabled(store.busy)
                    } footer: { Text(h.archive == nil ? "Archiving stops tracking from tomorrow and keeps your history." : "This habit is archived from tomorrow.") }
                }
            }.navigationTitle(habit == nil ? "New habit" : "Edit habit").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task {
                            let ok = await store.mutate("habits", ["id": habit?.id ?? newID, "name": name, "icon": icon, "color": color, "weekdays": weekdays.sorted()])
                            if ok { dismiss() }
                        } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || weekdays.isEmpty || store.busy || habit?.archive != nil)
                    }
                }.confirmationDialog("Archive this habit? Today remains available, and your history is kept.", isPresented: $confirmArchive, titleVisibility: .visible) {
                    Button("Archive", role: .destructive) { Task { if let h = habit, await store.mutate("archive", ["habit": h.id]) { dismiss() } } }
                }
        }
    }
}
struct WeekView: View {
    @Environment(AppStore.self) private var store
    @State private var partner = false
    @State private var offset = 0
    var dates: [String] { Tracking.week(containing: store.today, offset: offset) }
    var habits: [Habit] {
        let owner = partner ? store.partner?.id : store.me
        return (store.state.snapshot?.habits ?? []).filter { h in h.owner == owner && h.start <= dates[6] && (h.archive.map { $0 > dates[0] } ?? true) }
    }
    var totals: (Int, Int) {
        habits.reduce((0, 0)) { result, h in
            let t = Tracking.totals(habit: h, dates: dates, today: store.today) { store.isComplete(h.id, $0) }
            return (result.0 + t.done, result.1 + t.elapsed)
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    PersonPicker(partner: $partner)
                    SyncBanner()
                    HStack {
                        Button("Previous week", systemImage: "chevron.left") { offset -= 1 }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44)
                        Spacer()
                        Text("\(dates[0]) – \(dates[6])").font(.subheadline.bold()).multilineTextAlignment(.center)
                        Spacer()
                        Button("Next week", systemImage: "chevron.right") { offset += 1 }.labelStyle(.iconOnly).frame(minWidth: 44, minHeight: 44).disabled(offset >= 0)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Showing up, together.").font(.title2.bold())
                        Text("\(totals.0) of \(totals.1) scheduled check-ins completed").foregroundStyle(.secondary)
                        Text("Totals include scheduled days through today.").font(.caption).foregroundStyle(.secondary)
                    }
                    if habits.isEmpty { ContentUnavailableView("A clean slate", systemImage: "calendar", description: Text("No habits tracked in this week.")) }
                    else {
                        ScrollView(.horizontal) {
                            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 14) {
                                GridRow {
                                    Text("Habit").font(.caption.bold()).frame(width: 130, alignment: .leading)
                                    ForEach(Array(dates.enumerated()), id: \.offset) { i, date in
                                        VStack { Text(["M", "T", "W", "T", "F", "S", "S"][i]); Text(String(date.suffix(2))) }.font(.caption.bold()).frame(width: 44)
                                    }
                                    Text("Total").font(.caption.bold()).frame(width: 50)
                                }
                                ForEach(habits) { h in
                                    GridRow {
                                        Label(h.name, systemImage: h.icon).font(.subheadline).frame(width: 130, alignment: .leading)
                                        ForEach(dates, id: \.self) { date in
                                            let state = Tracking.state(habit: h, date: date, today: store.today, completed: store.isComplete(h.id, date))
                                            let eligible = !partner && h.owner == store.me && h.isScheduled(date) && [store.today, Tracking.adding(-1, to: store.today)].contains(date)
                                            Button { store.toggle(h, date) } label: {
                                                Image(systemName: symbol(state)).font(.title3).frame(width: 44, height: 44)
                                                    .foregroundStyle(state == .completed ? h.accent : .secondary)
                                                    .background(state == .completed ? h.accent.opacity(0.15) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 12))
                                            }.buttonStyle(.plain).disabled(!eligible)
                                                .accessibilityLabel("\(h.name), \(date), \(state.rawValue)")
                                                .accessibilityHint(eligible ? "Double tap to correct this day" : "")
                                        }
                                        let t = Tracking.totals(habit: h, dates: dates, today: store.today) { store.isComplete(h.id, $0) }
                                        Text("\(t.done)/\(t.elapsed)").font(.subheadline.monospacedDigit()).frame(width: 50)
                                    }
                                }
                            }.padding(.vertical, 6)
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach([CellState.completed, .missed, .open, .upcoming, .unscheduled], id: \.rawValue) { state in Label(state == .open ? "Today · still time" : state.rawValue.capitalized, systemImage: symbol(state)).font(.caption).foregroundStyle(.secondary) }
                        }
                        Text(partner ? "A window into your partner’s week." : "Tap today or yesterday to make a correction.").font(.footnote).foregroundStyle(.secondary)
                    }
                }.padding(20)
            }.background(Color(.systemGroupedBackground)).navigationTitle("Your week").refreshable { await store.sync() }
        }
    }
    func symbol(_ state: CellState) -> String {
        switch state { case .completed: "checkmark.circle.fill"; case .missed: "xmark.circle"; case .upcoming: "clock"; case .unscheduled: "minus"; case .open: "circle" }
    }
}
struct InboxView: View {
    @Environment(AppStore.self) private var store
    var inbox: [Nudge] { store.state.snapshot?.nudges.filter { $0.recipient == store.me } ?? [] }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("A little lift.").font(.title2.bold())
                        Text("Encouragement from your partner, whenever you need it.").foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                }
                if inbox.isEmpty { ContentUnavailableView("All quiet for now", systemImage: "hand.wave", description: Text("Nudges appear here even when notifications are off.")) }
                ForEach(inbox) { n in
                    Button { Task { await store.openNudge(habit: n.habit, nudge: n.id) } } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: n.read == 0 ? "envelope.badge.fill" : "envelope.open").foregroundStyle(.indigo)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(store.state.snapshot?.habits.first { $0.id == n.habit }?.name ?? "Your habit").font(.headline)
                                Text("A little encouragement from your partner. You’ve got this!").font(.subheadline)
                                Text(n.date).font(.caption).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary)
                        }.padding(.vertical, 8)
                    }.accessibilityLabel("\(n.read == 0 ? "Unread nudge" : "Nudge"), \(n.date). Open habit.")
                }
                Section {
                    #if PUSH_NOTIFICATIONS
                    Button("Enable nudge notifications") { Task { await store.enableNotifications() } }
                    #else
                    Label("Push notifications require a paid Apple Developer team.", systemImage: "bell.slash")
                    #endif
                } footer: { Text("Nudges remain available in the in-app inbox. Limits are one per habit and three per person per day.") }
            }.navigationTitle("Nudges").refreshable { await store.sync() }
        }
    }
}
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        NavigationStack {
            Form {
                Section("Your pair") {
                    ForEach(store.state.snapshot?.people ?? []) { person in LabeledContent(person.id == store.me ? "You" : "Partner", value: person.name) }
                    LabeledContent("Tracking timezone", value: store.state.snapshot?.timezone ?? "America/Toronto")
                }
                Section { Text("All habits and completion history are shared with your partner. Each person can change only their own habits. Tracking dates stay in your pair’s timezone when you travel.") }
                Section("Notifications") {
                    #if PUSH_NOTIFICATIONS
                    Button("Enable gentle nudges") { Task { await store.enableNotifications() } }
                    Button("Open notification settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                    #else
                    Text("Remote push requires a paid Apple Developer team. In-app nudges work now.")
                    #endif
                    Text("Only manual nudges. No automatic reminders.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Sync") {
                    SyncBanner()
                    if let message = store.syncMessage { Text(message).font(.footnote).foregroundStyle(.secondary) }
                    Text(store.busy ? "Syncing…" : "Refreshes every 15 seconds while active and whenever you return.").font(.footnote)
                    Button("Sync now") { Task { await store.sync() } }.disabled(store.busy)
                }
                Section { Button("Sign out", role: .destructive) { Task { await store.logout() } }.disabled(store.busy || !store.state.pending.isEmpty) }
            }.navigationTitle("Settings")
        }
    }
}
struct HabitFocusView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let habit: Habit
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 24) {
                Text("You’ve got this.").font(.largeTitle.bold())
                Text("A little encouragement from your partner.").foregroundStyle(.secondary)
                Button { store.toggle(habit, store.today) } label: { HabitCard(habit: habit, scheduled: habit.isScheduled(store.today)) }.buttonStyle(.plain)
                    .disabled(habit.owner != store.me || !habit.isScheduled(store.today))
                    .accessibilityLabel("\(habit.name), \(store.isComplete(habit.id, store.today) ? "completed" : "incomplete")")
                if habit.isScheduled(store.today) { Text("Tap to check in for today.").foregroundStyle(.secondary) }
                else { Text("This habit is not scheduled today. Your nudge is kept in the inbox.").foregroundStyle(.secondary) }
                SyncBanner()
                Spacer()
            }.padding(24).navigationTitle(habit.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Done") { store.focusedHabit = nil; dismiss() } }
        }
    }
}
