import Foundation

enum Constants {
    enum Defaults {
        static let scanFrequencyMinutes = 60
        static let scanConcurrency = 16
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
        static let notifyNewPlugins = "notifyNewPlugins"
        static let notifyUpdatedPlugins = "notifyUpdatedPlugins"
        static let notifyRemovedPlugins = "notifyRemovedPlugins"
        static let projectScanDirectories = "projectScanDirectories"
        static let scanProjectsOnLaunch = "scanProjectsOnLaunch"
        static let monitorProjectDirectories = "monitorProjectDirectories"
        static let debugVerboseLogging = "debugVerboseLogging"
        static let checkForAppUpdates = "checkForAppUpdates"
        static let pluginSortColumn = "pluginSortColumn"
        static let pluginSortAscending = "pluginSortAscending"
        static let projectSortColumn = "projectSortColumn"
        static let projectSortAscending = "projectSortAscending"
    }

    enum AppUpdateConfig {
        static let repoOwner = "bounceconnection"
        static let repoName = "pluginventory"
        static let githubAPIBase = "https://api.github.com"
    }

    enum NotificationIdentifiers {
        static let pluginInstalled = "com.bounceconnection.Pluginventory.pluginInstalled"
        static let pluginUpdated = "com.bounceconnection.Pluginventory.pluginUpdated"
        static let pluginRemoved = "com.bounceconnection.Pluginventory.pluginRemoved"
        static let scanCompleted = "com.bounceconnection.Pluginventory.scanCompleted"
    }

    enum CacheFiles {
        static let manifestCache = "manifest_cache.json"
    }

    enum AssetNames {
        static let menuBarIcon = "MenuBarIcon"
        static let appIcon = "AppIcon"
    }

    static let defaultScanLocations: [(path: String, format: PluginFormat)] = [
        ("/Library/Audio/Plug-Ins/Components", .au),
        ("/Library/Audio/Plug-Ins/CLAP", .clap),
        ("/Library/Audio/Plug-Ins/VST", .vst2),
        ("/Library/Audio/Plug-Ins/VST3", .vst3),
    ]

    static let defaultProjectScanDirectories: [String] = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/Documents/Ableton Projects"]
    }()
}
