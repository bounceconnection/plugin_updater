import Foundation

enum Constants {
    enum Defaults {
        static let scanFrequencyMinutes = 60
        static let scanConcurrency = 8
        static let fsEventsDebounceSeconds: TimeInterval = 3.0
        static let manifestURL = ""
    }

    enum UserDefaultsKeys {
        static let scanFrequency = "scanFrequencyMinutes"
        static let notificationsEnabled = "notificationsEnabled"
        static let manifestURL = "manifestURL"
        static let launchAtLogin = "launchAtLogin"
        static let lastScanDate = "lastScanDate"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    enum NotificationIdentifiers {
        static let pluginInstalled = "com.tomioueda.PluginUpdater.pluginInstalled"
        static let pluginUpdated = "com.tomioueda.PluginUpdater.pluginUpdated"
        static let pluginRemoved = "com.tomioueda.PluginUpdater.pluginRemoved"
        static let scanCompleted = "com.tomioueda.PluginUpdater.scanCompleted"
    }

    enum AssetNames {
        static let menuBarIcon = "MenuBarIcon"
        static let appIcon = "AppIcon"
    }

    static let defaultScanLocations: [(path: String, format: PluginFormat)] = [
        ("/Library/Audio/Plug-Ins/VST3", .vst3),
        ("~/Library/Audio/Plug-Ins/VST3", .vst3),
        ("/Library/Audio/Plug-Ins/Components", .au),
        ("~/Library/Audio/Plug-Ins/Components", .au),
        ("/Library/Audio/Plug-Ins/CLAP", .clap),
        ("~/Library/Audio/Plug-Ins/CLAP", .clap),
    ]
}
