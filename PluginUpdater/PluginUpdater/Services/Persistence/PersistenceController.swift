import Foundation
import SwiftData

enum PersistenceController {
    /// Migrates SwiftData store and UserDefaults from old bundle ID (`com.tomioueda.PluginUpdater`)
    /// to new bundle ID (`com.bounceconnection.PluginUpdater`). Safe to call multiple times.
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
        let appDir = appSupport.appendingPathComponent("com.bounceconnection.PluginUpdater")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("PluginUpdater.store")
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
