import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif

struct HabitDetailView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("calmCards") private var calm = false
    let id: String
    @State private var editing: Habit?
    var body: some View {
        if let habit = store.state.snapshot?.habits.first(where: { $0.id == id }) { content(habit) }
        else { ContentUnavailableView("Habit unavailable", systemImage: "questionmark.circle") }
    }
    func content(_ habit: Habit) -> some View {
        let mine = habit.owner == store.me
        let dates = Tracking.week(containing: store.today)
        let week = store.week(habit)
        let growth = store.growth(habit)
        return List {
            // The hero lives in a header so list row clipping doesn't override its corners.
            Section {
                SevenDayStrip(habit: habit, dates: dates, ink: CardInk(habit: habit, tinted: false)).padding(.vertical, 8)
                LabeledContent("Done") {
                    Text("\(week.done) of \(week.elapsed)").font(.system(.body, design: .rounded, weight: .semibold).monospacedDigit())
                }
            } header: {
                VStack(alignment: .leading, spacing: 20) {
                    hero(habit)
                    stats(habit, growth)
                    Text("This week").padding(.horizontal, Metric.padding)
                }.textCase(nil).listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
            if mine { corrections(habit) } else { nudge(habit) }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(habit.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { if mine { Button("Edit") { editing = habit } } }
        .sheet(item: $editing) { HabitEditor(habit: $0) }
    }
    func hero(_ habit: Habit) -> some View {
        let scheduled = habit.isScheduled(store.today)
        let tinted = scheduled && !calm
        let ink = CardInk(habit: habit, tinted: tinted, paused: !scheduled)
        let growth = store.growth(habit)
        let done = store.isComplete(habit.id, store.today)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    StageChip(growth: growth, ink: ink)
                    Text(Palette.species(habit.color)).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(ink.primary)
                }
                Spacer()
                if store.canCorrect(habit, store.today) { WaterButton(habit: habit, ink: ink, diameter: 56) }
            }
            GrowthBar(progress: growth.progress, tint: tinted ? ink.primary : habit.accent, track: ink.track, height: 12)
            Text(growth.stage.next.map { "\(Self.points($0.threshold - growth.points)) growth to \($0.name)" } ?? "Fully grown")
                .font(.subheadline.weight(.medium)).foregroundStyle(ink.secondary)
        }
        .padding(.top, 150)
        .padding(Metric.padding).padding(.bottom, Metric.lip)
        .background { CardBackground(habit: habit, tinted: tinted) }
        .padding(.top, 200)
        .overlay(alignment: .top) {
            TreeView(spec: store.tree(habit), interactive: true).frame(height: 360).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Palette.species(habit.color)), \(growth.stage.name)\(growth.wilting ? ", thirsty" : ""), \(scheduled ? (done ? "done today" : "not done today") : "rest day")")
        .accessibilityAction(named: done ? "Undo check-in" : "Water") { withAnimation(.standard) { store.toggle(habit, store.today) } }
    }
    func stats(_ habit: Habit, _ growth: Growth) -> some View {
        let streak = store.streak(habit)
        return HStack(spacing: Metric.gutter) {
            stat("Streak", "\(streak)", "flame.fill", Palette.gold)
            stat("Best", "\(growth.bestStreak)", "trophy.fill", .orange)
            stat("Health", "\(Int((growth.vitality * 100).rounded()))%", growth.wilting ? "drop.triangle.fill" : "drop.fill", growth.wilting ? .brown : .blue)
        }
    }
    func stat(_ title: String, _ value: String, _ symbol: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).font(.system(.title3, design: .rounded, weight: .bold).monospacedDigit()).foregroundStyle(Color.primary)
            Text(title).font(.caption.weight(.medium)).foregroundStyle(Color.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metric.padding).padding(.bottom, Metric.lip)
        .background { CardBackground(habit: nil, tinted: false) }
        .accessibilityElement(children: .combine)
    }
    static func points(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(0...1))) }
    @ViewBuilder func corrections(_ habit: Habit) -> some View {
        let days = [store.today, Tracking.adding(-1, to: store.today)].filter { store.canCorrect(habit, $0) }
        Section {
            if days.isEmpty { Text("Not scheduled today or yesterday.").foregroundStyle(.secondary) }
            ForEach(days, id: \.self) { date in
                Toggle(date == store.today ? "Today" : "Yesterday", isOn: Binding(get: { store.isComplete(habit.id, date) }, set: { _ in
                    withAnimation(.standard) { store.toggle(habit, date) }
                })).tint(habit.accent)
            }
        } header: { Text("Check-ins") } footer: { Text("You can change today and yesterday.") }
    }
    @ViewBuilder func nudge(_ habit: Habit) -> some View {
        Section {
            if store.nudgeSent(habit) { Label("Nudge sent", systemImage: "checkmark").foregroundStyle(.secondary) }
            else if store.isComplete(habit.id, store.today) { Text("\(store.name(habit.owner)) checked in today.").foregroundStyle(.secondary) }
            else if !habit.isScheduled(store.today) { Text("Not scheduled today.").foregroundStyle(.secondary) }
            else {
                Button("Send nudge") { Task { await store.mutate("nudge", ["habit": habit.id]) } }.disabled(!store.nudgeAllowed(habit) || store.busy)
            }
        } footer: { Text("You can send one nudge per habit and three a day.") }
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
    private let icons = ["figure.walk", "figure.run", "dumbbell.fill", "book.fill", "pencil", "brain.head.profile", "drop.fill",
                         "fork.knife", "leaf.fill", "sun.max.fill", "moon.fill", "bed.double.fill", "heart.fill", "music.note"]
    init(habit: Habit?) {
        self.habit = habit
        _name = State(initialValue: habit?.name ?? "")
        _icon = State(initialValue: habit?.icon ?? "figure.walk")
        _color = State(initialValue: habit?.color ?? "blue")
        _weekdays = State(initialValue: Set(habit?.schedules.last?.weekdays ?? Array(1...7)))
    }
    var body: some View {
        let accent = Palette.color(color)
        let onAccent: Color = ["yellow", "mint"].contains(color) ? .black.opacity(0.85) : .white
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Read 20 pages")).onChange(of: name) { _, value in name = String(value.prefix(60)) }
                }
                Section {
                    // A preview of this species as a young tree.
                    TreeView(spec: TreeSpec(id: habit?.id ?? newID, color: color, level: 3.4, vitality: 1)).frame(height: 170)
                        .frame(maxWidth: .infinity).accessibilityHidden(true)
                    swatches(Palette.names) { option in
                        Circle().fill(Palette.color(option)).frame(width: 32, height: 32).overlay {
                            if option == color { Image(systemName: "checkmark").font(.footnote.weight(.bold)).foregroundStyle(onAccent) }
                        }
                    } selected: { $0 == color } select: { color = $0 } label: { Palette.species($0) }
                } header: { Text("Tree") } footer: { Text("\(Palette.species(color)). Your tree grows with every check-in, and faster on a streak.") }
                Section("Symbol") {
                    swatches(icons) { option in
                        Image(systemName: option).font(.body).frame(width: 40, height: 40)
                            .foregroundStyle(option == icon ? onAccent : .secondary)
                            .background(option == icon ? accent : Palette.fill, in: Circle())
                    } selected: { $0 == icon } select: { icon = $0 } label: { $0.replacingOccurrences(of: ".fill", with: "").replacingOccurrences(of: ".", with: " ") }
                }
                Section {
                    Toggle("Every day", isOn: Binding(get: { weekdays.count == 7 }, set: { weekdays = $0 ? Set(1...7) : [] }))
                    ForEach(1...7, id: \.self) { day in
                        Toggle(Calendar.current.standaloneWeekdaySymbols[day % 7], isOn: Binding(get: { weekdays.contains(day) }, set: { if $0 { weekdays.insert(day) } else { weekdays.remove(day) } }))
                    }
                } header: { Text("Schedule") } footer: { Text(habit == nil ? "Starts today. Earlier days don’t count as missed." : "Schedule changes start tomorrow. Past weeks keep their schedule.") }
                if let h = habit {
                    Section {
                        Button("Archive habit", role: .destructive) { confirmArchive = true }.disabled(store.busy || h.archive != nil)
                    } footer: { Text(h.archive == nil ? "Tracking stops tomorrow. Your history is kept." : "This habit is archived from tomorrow.") }
                }
            }
            .navigationTitle(habit == nil ? "New habit" : "Edit habit").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(habit == nil ? "Add" : "Save") { Task {
                        let ok = await store.mutate("habits", ["id": habit?.id ?? newID, "name": name, "icon": icon, "color": color, "weekdays": weekdays.sorted()])
                        if ok { dismiss() }
                    } }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || weekdays.isEmpty || store.busy || habit?.archive != nil)
                }
            }
            .confirmationDialog("Archive this habit? You can still check in today, and your history is kept.", isPresented: $confirmArchive, titleVisibility: .visible) {
                Button("Archive habit", role: .destructive) { Task { if let h = habit, await store.mutate("archive", ["habit": h.id]) { dismiss() } } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    func swatches<Swatch: View>(_ options: [String], @ViewBuilder swatch: @escaping (String) -> Swatch, selected: @escaping (String) -> Bool, select: @escaping (String) -> Void, label: @escaping (String) -> String) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button { select(option) } label: { swatch(option).frame(width: 44, height: 44).contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(label(option))
                    .accessibilityAddTraits(selected(option) ? .isSelected : [])
            }
        }.padding(.vertical, 8)
    }
}
