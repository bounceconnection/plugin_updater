import Foundation
import UserNotifications

final class NotificationManager: @unchecked Sendable {
    static let shared = NotificationManager()

    /// Whether we're running in a proper .app bundle (required for UNUserNotificationCenter)
    private let hasBundleIdentifier = Bundle.main.bundleIdentifier != nil

    private init() {}

    func requestAuthorization() async -> Bool {
        guard hasBundleIdentifier else { return false }
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func notifyChanges(_ changes: [PluginReconciler.PluginChange]) {
        guard UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.notificationsEnabled) else { return }
        guard !changes.isEmpty else { return }

        let added = changes.filter { if case .added = $0.changeType { return true }; return false }
        let updated = changes.filter { if case .updated = $0.changeType { return true }; return false }
        let removed = changes.filter { if case .removed = $0.changeType { return true }; return false }

        if !added.isEmpty && UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.notifyNewPlugins) {
            send(
                title: "\(added.count) New Plugin\(added.count == 1 ? "" : "s")",
                body: summaryText(for: added),
                identifier: Constants.NotificationIdentifiers.pluginInstalled
            )
        }

        if !updated.isEmpty && UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.notifyUpdatedPlugins) {
            send(
                title: "\(updated.count) Plugin\(updated.count == 1 ? "" : "s") Updated",
                body: summaryText(for: updated),
                identifier: Constants.NotificationIdentifiers.pluginUpdated
            )
        }

        if !removed.isEmpty && UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.notifyRemovedPlugins) {
            send(
                title: "\(removed.count) Plugin\(removed.count == 1 ? "" : "s") Removed",
                body: summaryText(for: removed),
                identifier: Constants.NotificationIdentifiers.pluginRemoved
            )
        }
    }

    private func summaryText(for changes: [PluginReconciler.PluginChange]) -> String {
        let names = changes.prefix(3).map(\.pluginName).joined(separator: ", ")
        if changes.count > 3 {
            return "\(names) and \(changes.count - 3) more"
        }
        return names
    }

    private func send(title: String, body: String, identifier: String) {
        guard hasBundleIdentifier else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "\(identifier).\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                AppLogger.shared.error(
                    "Notification delivery failed: \(error.localizedDescription)",
                    category: "notifications"
                )
            } else {
                AppLogger.shared.info("Notification sent: \(title)", category: "notifications")
            }
        }
    }
}
