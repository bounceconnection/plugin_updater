import SwiftUI

struct NotificationSettingsView: View {
    @AppStorage(Constants.UserDefaultsKeys.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(Constants.UserDefaultsKeys.notifyNewPlugins) private var notifyNewPlugins = true
    @AppStorage(Constants.UserDefaultsKeys.notifyUpdatedPlugins) private var notifyUpdatedPlugins = true
    @AppStorage(Constants.UserDefaultsKeys.notifyRemovedPlugins) private var notifyRemovedPlugins = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable notifications", isOn: $notificationsEnabled)
            }

            Section("Notify me about") {
                Toggle("New plugins detected", isOn: $notifyNewPlugins)
                Toggle("Plugin updates", isOn: $notifyUpdatedPlugins)
                Toggle("Plugin removals", isOn: $notifyRemovedPlugins)
            }
            .disabled(!notificationsEnabled)
        }
    }
}
