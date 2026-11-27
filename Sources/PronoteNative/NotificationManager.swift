import AppKit
import Foundation
import UserNotifications

@MainActor
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    var onSelectSection: ((AppSection) -> Void)?

    private var isAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    func configure(onSelectSection: @escaping (AppSection) -> Void) {
        self.onSelectSection = onSelectSection
        guard isAppBundle else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        guard isAppBundle else { return .notDetermined }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        guard isAppBundle else { return false }
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func send(title: String, body: String, section: AppSection, identifier: String = UUID().uuidString) {
        guard isAppBundle else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["section": section.rawValue]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.2, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func sendTestNotification() {
        send(
            title: "Pronote Native",
            body: "Les notifications fonctionnent correctement !",
            section: .home
        )
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let rawSection = response.notification.request.content.userInfo["section"] as? String
        if let rawSection, let section = AppSection(rawValue: rawSection) {
            Task { @MainActor in
                NotificationManager.shared.onSelectSection?(section)
            }
        }
        completionHandler()
    }
}
