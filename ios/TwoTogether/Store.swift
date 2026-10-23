import SwiftUI
#if canImport(HabitCore)
import HabitCore
#endif
import Security
import UserNotifications

struct Account: Codable { var server: String; var key: String }
typealias DiskState = CachedState
struct ServiceError: Error, LocalizedError {
    let status: Int; let message: String
    var errorDescription: String? { message }
}
enum Vault {
    static let service = "TwoTogether.account"
    static func read() -> Account? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecReturnData as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Account.self, from: data)
    }
    static func write(_ account: Account?) throws {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
        if let account {
            let data = try JSONEncoder().encode(account)
            let status = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
            if status == errSecItemNotFound {
                var add = q; add[kSecValueData as String] = data
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw ServiceError(status: 0, message: "Couldn’t save your account securely.") }
            } else if status != errSecSuccess { throw ServiceError(status: 0, message: "Couldn’t update your saved account.") }
        } else { SecItemDelete(q as CFDictionary) }
    }
}

@MainActor @Observable final class AppStore {
    var account: Account?
    var state = DiskState()
    var busy = false
    var error: String?
    var syncMessage: String?
    var focusedHabit: String?
    var selectedTab = 0
    var deviceToken: String?
    var today: String { Tracking.today(timezone: state.snapshot?.timezone ?? "America/Toronto") }
    var me: String { state.snapshot?.me ?? "" }
    var partner: Person? { state.snapshot?.people.first { $0.id != me } }
    private var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("TwoTogether/state.json")
    }
    init() {
        account = Vault.read()
        if account != nil {
            do { state = try LocalCache(url: file).load() }
            catch { self.error = "Couldn’t read your saved check-ins. " + error.localizedDescription }
        }
    }
    func persist() throws {
        try LocalCache(url: file).save(state)
    }
    func request(_ path: String, body: [String: Any]? = nil, using supplied: Account? = nil) async throws -> Snapshot {
        guard let a = supplied ?? account, let base = URL(string: a.server), let scheme = base.scheme, scheme == "https" || (scheme == "http" && ["localhost", "127.0.0.1"].contains(base.host ?? "")) else { throw ServiceError(status: 0, message: "Use an HTTPS server address. HTTP works only for localhost.") }
        let url = base.appendingPathComponent("v1/" + path)
        var request = URLRequest(url: url); request.timeoutInterval = 20
        request.setValue("Bearer " + a.key, forHTTPHeaderField: "Authorization")
        if let body {
            request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: String])?["error"] ?? "Couldn’t reach the server. Check your connection and try again."
            throw ServiceError(status: status, message: message)
        }
        return try JSONDecoder().decode(Snapshot.self, from: data)
    }
    func login(server: String, key: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let a = Account(server: server.trimmingCharacters(in: .whitespacesAndNewlines), key: key.trimmingCharacters(in: .whitespacesAndNewlines))
            let snapshot = try await request("snapshot", using: a)
            try Vault.write(a)
            state = DiskState(snapshot: snapshot); account = a
            try persist()
            if let token = deviceToken { try await registerDevice(token) }
        } catch { self.error = error.localizedDescription }
    }
    func isComplete(_ habit: String, _ date: String) -> Bool {
        guard let s = state.snapshot else { return false }
        return Tracking.completed(habit, on: date, snapshot: s, pending: state.pending)
    }
    func toggle(_ habit: Habit, _ date: String) {
        guard canCorrect(habit, date) else { return }
        let prior = state
        state.pending.append(PendingCompletion(habit: habit.id, date: date, completed: !isComplete(habit.id, date)))
        do { try persist() } catch { state = prior; self.error = "Couldn’t save your check-in on this device. Try again."; return }
        Task { await sync() }
    }
    func sync() async {
        guard account != nil, !busy else { return }
        busy = true; defer { busy = false }
        do {
            while let op = state.pending.first {
                do {
                    let snapshot = try await request("completion", body: ["operation": op.id, "habit": op.habit, "date": op.date, "completed": op.completed])
                    state.snapshot = snapshot
                    state.pending.removeAll { $0.id == op.id }
                    try persist()
                } catch let error as ServiceError where [403, 404, 409, 422].contains(error.status) {
                    state.pending.removeAll { $0.id == op.id }; try persist()
                    self.error = "Couldn’t apply a saved check-in. " + error.message
                }
            }
            state.snapshot = try await request("snapshot"); try persist(); syncMessage = nil
        } catch { syncMessage = "Couldn’t sync. Check your connection and try again." }
    }
    @discardableResult func mutate(_ endpoint: String, _ body: [String: Any]) async -> Bool {
        guard !busy, state.pending.isEmpty else { error = "Wait for your check-ins to sync, then try again."; return false }
        busy = true; defer { busy = false }
        do { state.snapshot = try await request(endpoint, body: body); try persist(); return true }
        catch { self.error = error.localizedDescription; return false }
    }
    func nudgeAllowed(_ h: Habit) -> Bool {
        guard let s = state.snapshot else { return false }
        let sent = s.nudges.filter { $0.sender == me && $0.date == today }
        return h.owner != me && h.isScheduled(today) && !isComplete(h.id, today) && sent.count < 3 && !sent.contains { $0.habit == h.id }
    }
    func nudgeSent(_ h: Habit) -> Bool {
        state.snapshot?.nudges.contains { $0.sender == me && $0.habit == h.id && $0.date == today } ?? false
    }
    func streak(_ h: Habit) -> Int { Tracking.streak(habit: h, today: today) { isComplete(h.id, $0) } }
    func week(_ h: Habit, offset: Int = 0) -> (done: Int, elapsed: Int) {
        Tracking.totals(habit: h, dates: Tracking.week(containing: today, offset: offset), today: today) { isComplete(h.id, $0) }
    }
    func canCorrect(_ h: Habit, _ date: String) -> Bool {
        h.owner == me && h.isScheduled(date) && [today, Tracking.adding(-1, to: today)].contains(date)
    }
    func name(_ person: String) -> String { state.snapshot?.people.first { $0.id == person }?.name ?? "Your partner" }
    func lastCheckIn(_ person: String) -> Date? {
        guard let s = state.snapshot else { return nil }
        let owned = Set(s.habits.filter { $0.owner == person }.map(\.id))
        return s.completions.filter { owned.contains($0.habit) }.compactMap { Self.instant($0.completed_at) }.max()
    }
    // Server stamps carry microseconds, which ISO8601DateFormatter can't parse.
    static func instant(_ stamp: String) -> Date? {
        ISO8601DateFormatter().date(from: stamp.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression))
    }
    func enableNotifications() async {
        #if PUSH_NOTIFICATIONS
        do {
            let accepted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            if accepted { UIApplication.shared.registerForRemoteNotifications() }
        } catch { self.error = error.localizedDescription }
        #else
        self.error = "Notifications need an Apple Developer Program team. Nudges still appear in Partners."
        #endif
    }
    func registerDevice(_ token: String) async throws {
        deviceToken = token
        guard account != nil else { return }
        _ = try await request("device", body: ["token": token])
    }
    func logout() async {
        guard state.pending.isEmpty, !busy else { error = "Sync your check-ins before signing out."; return }
        // Keep the account signed in if device deregistration fails, avoiding pushes to a signed-out device.
        do {
            if let token = deviceToken { _ = try await request("logout", body: ["token": token]) }
            try Vault.write(nil)
            try? FileManager.default.removeItem(at: file)
            account = nil; state = DiskState(); focusedHabit = nil; selectedTab = 0
        } catch { self.error = error.localizedDescription }
    }
    func openNudge(habit: String, nudge: String?) async {
        focusedHabit = habit; selectedTab = 0
        if let nudge { _ = await mutate("read", ["id": nudge]) }
    }
}
