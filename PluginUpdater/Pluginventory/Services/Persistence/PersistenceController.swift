import Foundation
import SwiftData

enum PersistenceController {
    /// Chained migration for SwiftData store and UserDefaults. Safe to call multiple times.
    /// 1. `com.tomioueda.PluginUpdater` → `com.bounceconnection.PluginUpdater`
    /// 2. `com.bounceconnection.PluginUpdater` → `com.bounceconnection.Pluginventory`
    static func migrateFromOldBundleID() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let oldDir = appSupport.appendingPathComponent("com.tomioueda.PluginUpdater")
        let newDir = appSupport.appendingPathComponent("com.bounceconnection.PluginUpdater")

        // Move SwiftData store directory if old exists and new doesn't
        if fm.fileExists(atPath: oldDir.path) && !fm.fileExists(atPath: newDir.path) {
            try? fm.moveItem(at: oldDir, to: newDir)
        }

        // Migrate UserDefaults (one-time)
        if !UserDefaults.standard.bool(forKey: "didMigrateFromOldBundleID") {
            if let oldDefaults = UserDefaults(suiteName: "com.tomioueda.PluginUpdater") {
                let keysToMigrate = [
                    Constants.UserDefaultsKeys.scanFrequency,
                    Constants.UserDefaultsKeys.notificationsEnabled,
                    Constants.UserDefaultsKeys.manifestURL,
                    Constants.UserDefaultsKeys.launchAtLogin,
                    Constants.UserDefaultsKeys.lastScanDate,
                    Constants.UserDefaultsKeys.hasCompletedOnboarding,
                    Constants.UserDefaultsKeys.notifyNewPlugins,
                    Constants.UserDefaultsKeys.notifyUpdatedPlugins,
                    Constants.UserDefaultsKeys.notifyRemovedPlugins,
                    Constants.UserDefaultsKeys.projectScanDirectories,
                    Constants.UserDefaultsKeys.scanProjectsOnLaunch,
                    Constants.UserDefaultsKeys.monitorProjectDirectories,
                    Constants.UserDefaultsKeys.debugVerboseLogging,
                    Constants.UserDefaultsKeys.checkForAppUpdates,
                ]
                for key in keysToMigrate {
                    if let value = oldDefaults.object(forKey: key) {
                        UserDefaults.standard.set(value, forKey: key)
                    }
                }
            }
            UserDefaults.standard.set(true, forKey: "didMigrateFromOldBundleID")
        }

        // --- Step 2: com.bounceconnection.PluginUpdater → com.bounceconnection.Pluginventory ---
        let pluginUpdaterDir = appSupport.appendingPathComponent("com.bounceconnection.PluginUpdater")
        let pluginventoryDir = appSupport.appendingPathComponent("com.bounceconnection.Pluginventory")

        // Move SwiftData store directory if old exists and new doesn't
        if fm.fileExists(atPath: pluginUpdaterDir.path) && !fm.fileExists(atPath: pluginventoryDir.path) {
            try? fm.moveItem(at: pluginUpdaterDir, to: pluginventoryDir)
        }

        // Rename store file inside the new directory
        let oldStoreFile = pluginventoryDir.appendingPathComponent("PluginUpdater.store")
        let newStoreFile = pluginventoryDir.appendingPathComponent("Pluginventory.store")
        if fm.fileExists(atPath: oldStoreFile.path) && !fm.fileExists(atPath: newStoreFile.path) {
            try? fm.moveItem(at: oldStoreFile, to: newStoreFile)
        }

        // Migrate UserDefaults (one-time)
        if !UserDefaults.standard.bool(forKey: "didMigrateFromPluginUpdater") {
            if let oldDefaults = UserDefaults(suiteName: "com.bounceconnection.PluginUpdater") {
                let keysToMigrate = [
                    Constants.UserDefaultsKeys.scanFrequency,
                    Constants.UserDefaultsKeys.notificationsEnabled,
                    Constants.UserDefaultsKeys.manifestURL,
                    Constants.UserDefaultsKeys.launchAtLogin,
                    Constants.UserDefaultsKeys.lastScanDate,
                    Constants.UserDefaultsKeys.hasCompletedOnboarding,
                    Constants.UserDefaultsKeys.notifyNewPlugins,
                    Constants.UserDefaultsKeys.notifyUpdatedPlugins,
                    Constants.UserDefaultsKeys.notifyRemovedPlugins,
                    Constants.UserDefaultsKeys.projectScanDirectories,
                    Constants.UserDefaultsKeys.scanProjectsOnLaunch,
                    Constants.UserDefaultsKeys.monitorProjectDirectories,
                    Constants.UserDefaultsKeys.debugVerboseLogging,
                    Constants.UserDefaultsKeys.checkForAppUpdates,
                    Constants.UserDefaultsKeys.pluginSortColumn,
                    Constants.UserDefaultsKeys.pluginSortAscending,
                    Constants.UserDefaultsKeys.projectSortColumn,
                    Constants.UserDefaultsKeys.projectSortAscending,
                ]
                for key in keysToMigrate {
                    if let value = oldDefaults.object(forKey: key) {
                        UserDefaults.standard.set(value, forKey: key)
                    }
                }
            }
            UserDefaults.standard.set(true, forKey: "didMigrateFromPluginUpdater")
        }
    }

    static let modelSchema = Schema([
        Plugin.self,
        PluginVersion.self,
        VendorInfo.self,
        ScanLocation.self,
        AbletonProject.self,
        AbletonProjectPlugin.self,
    ])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(
                schema: modelSchema,
                isStoredInMemoryOnly: true
            )
        } else {
            config = ModelConfiguration(
                schema: modelSchema,
                url: storeURL
            )
        }
        return try ModelContainer(for: modelSchema, configurations: [config])
    }

    static var storeURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("com.bounceconnection.Pluginventory")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("Pluginventory.store")
    }

    @MainActor
    static func seedDefaultScanLocations(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<ScanLocation>()
        let existing = try context.fetch(descriptor)

        if existing.isEmpty {
            for location in Constants.defaultScanLocations {
                let scanLocation = ScanLocation(
                    path: location.path,
                    format: location.format,
                    isDefault: true,
                    isEnabled: true
                )
                context.insert(scanLocation)
            }
            try context.save()
            return
        }

        // Migration: add VST2 defaults for existing users
        let hasVST2 = existing.contains { $0.format == .vst2 }
        if !hasVST2 {
            for location in Constants.defaultScanLocations where location.format == .vst2 {
                let scanLocation = ScanLocation(
                    path: location.path,
                    format: location.format,
                    isDefault: true,
                    isEnabled: true
                )
                context.insert(scanLocation)
            }
            try context.save()
        }

        // Migration: remove ~/Library default locations (plugins are never installed there)
        let userDefaults = existing.filter { $0.isDefault && $0.path.hasPrefix("~/") }
        if !userDefaults.isEmpty {
            for location in userDefaults {
                context.delete(location)
            }
            try context.save()
        }
    }
}
