import SwiftUI
import UserNotifications

@MainActor final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var pendingFocus: (habit: String, nudge: String?)?
    var store: AppStore? {
        didSet {
            if let focus = pendingFocus {
                pendingFocus = nil
                Task { await store?.openNudge(habit: focus.habit, nudge: focus.nudge) }
            }
        }
    }
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if PUSH_NOTIFICATIONS
        UNUserNotificationCenter.current().delegate = self
        #endif
        return true
    }
    #if PUSH_NOTIFICATIONS
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { try? await store?.registerDevice(token) }
    }
    #endif
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) { completionHandler([.banner, .sound]) }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        if let habit = info["habit"] as? String {
            let nudge = info["nudge"] as? String
            Task { @MainActor in
                if store == nil { pendingFocus = (habit, nudge) }
                else { await store?.openNudge(habit: habit, nudge: nudge) }
            }
        }
        completionHandler()
    }
}
@main struct TwoTogetherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @State private var store = AppStore()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            RootView().environment(store).tint(.indigo)
                .onAppear {
                    delegate.store = store
                    #if PUSH_NOTIFICATIONS
                    UIApplication.shared.registerForRemoteNotifications()
                    #endif
                }
                .task {
                    while !Task.isCancelled {
                        if phase == .active { await store.sync() }
                        try? await Task.sleep(for: .seconds(15))
                    }
                }
                .onChange(of: phase) { _, next in if next == .active { Task { await store.sync() } } }
        }
    }
}
