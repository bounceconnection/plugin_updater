import Foundation
import SwiftData

@ModelActor
actor PluginReconciler {

    struct ReconciliationResult: Sendable {
        let newPlugins: Int
        let updatedPlugins: Int
        let removedPlugins: Int
        let unchangedPlugins: Int
        let totalProcessed: Int
        let changes: [PluginChange]
    }

    struct PluginChange: Sendable {
        enum ChangeType: Sendable {
            case added
            case updated(oldVersion: String, newVersion: String)
            case removed
            case reappeared
        }

        let pluginName: String
        let bundleIdentifier: String
        let changeType: ChangeType
    }

    /// Reconciles scanned plugin metadata against the existing SwiftData store.
    /// Detects new, updated, removed, and reappeared plugins in a single pass.
    /// Set `fullScan` to false for incremental scans so unseen plugins are not marked as removed.
    func reconcile(scannedPlugins: [PluginMetadata], fullScan: Bool = true) throws -> ReconciliationResult {
        // Deduplicate by bundleIdentifier — when the same plugin exists in both
        // system and user directories, keep the one with the newer version
        var dedupedByID: [String: PluginMetadata] = [:]
        for metadata in scannedPlugins {
            if let existing = dedupedByID[metadata.bundleIdentifier] {
                if metadata.version.isNewerVersion(than: existing.version) {
                    dedupedByID[metadata.bundleIdentifier] = metadata
                }
            } else {
                dedupedByID[metadata.bundleIdentifier] = metadata
            }
        }
        let uniquePlugins = Array(dedupedByID.values)

        // Fetch all existing plugins
        let descriptor = FetchDescriptor<Plugin>()
        let existingPlugins = try modelContext.fetch(descriptor)

        // Index existing plugins by bundleIdentifier for O(1) lookup
        var existingByBundleID: [String: Plugin] = [:]
        for plugin in existingPlugins {
            existingByBundleID[plugin.bundleIdentifier] = plugin
        }

        // Build vendor cache from existing records
        let vendorDescriptor = FetchDescriptor<VendorInfo>()
        let existingVendors = try modelContext.fetch(vendorDescriptor)
        var vendorsByName: [String: VendorInfo] = [:]
        for vendor in existingVendors {
            vendorsByName[vendor.name] = vendor
        }

        var seenBundleIDs: Set<String> = []
        var newCount = 0
        var updatedCount = 0
        var unchangedCount = 0
        var changes: [PluginChange] = []

        for metadata in uniquePlugins {
            seenBundleIDs.insert(metadata.bundleIdentifier)

            if let existing = existingByBundleID[metadata.bundleIdentifier] {
                processExistingPlugin(
                    existing,
                    metadata: metadata,
                    vendorCache: &vendorsByName,
                    updatedCount: &updatedCount,
                    unchangedCount: &unchangedCount,
                    changes: &changes
                )
            } else {
                insertNewPlugin(
                    metadata: metadata,
                    vendorCache: &vendorsByName
                )
                newCount += 1
                changes.append(PluginChange(
                    pluginName: metadata.name,
                    bundleIdentifier: metadata.bundleIdentifier,
                    changeType: .added
                ))
            }
        }

        // Soft-delete plugins that were not seen (only during full scans)
        var removedCount = 0
        if fullScan {
            removedCount = markRemovedPlugins(
                existingPlugins: existingPlugins,
                seenBundleIDs: seenBundleIDs,
                changes: &changes
            )
        }

        // Single save for all changes
        try modelContext.save()

        return ReconciliationResult(
            newPlugins: newCount,
            updatedPlugins: updatedCount,
            removedPlugins: removedCount,
            unchangedPlugins: unchangedCount,
            totalProcessed: uniquePlugins.count,
            changes: changes
        )
    }

    // MARK: - Private

    private func processExistingPlugin(
        _ existing: Plugin,
        metadata: PluginMetadata,
        vendorCache: inout [String: VendorInfo],
        updatedCount: inout Int,
        unchangedCount: inout Int,
        changes: inout [PluginChange]
    ) {
        existing.lastSeenDate = .now
        existing.path = metadata.url.path
        existing.name = metadata.name

        // Plugin reappeared after being removed
        if existing.isRemoved {
            existing.isRemoved = false
            changes.append(PluginChange(
                pluginName: metadata.name,
                bundleIdentifier: metadata.bundleIdentifier,
                changeType: .reappeared
            ))
        }

        // Version changed — record history
        if metadata.version != existing.currentVersion {
            let oldVersion = existing.currentVersion
            let versionRecord = PluginVersion(
                version: metadata.version,
                previousVersion: oldVersion
            )
            existing.versionHistory.append(versionRecord)
            existing.currentVersion = metadata.version
            updatedCount += 1
            changes.append(PluginChange(
                pluginName: metadata.name,
                bundleIdentifier: metadata.bundleIdentifier,
                changeType: .updated(oldVersion: oldVersion, newVersion: metadata.version)
            ))
        } else {
            unchangedCount += 1
        }

        // Update vendor if changed
        if existing.vendorName != metadata.vendorName {
            existing.vendorName = metadata.vendorName
            existing.vendor = findOrCreateVendor(name: metadata.vendorName, cache: &vendorCache)
        }
    }

    private func insertNewPlugin(
        metadata: PluginMetadata,
        vendorCache: inout [String: VendorInfo]
    ) {
        let plugin = Plugin(
            name: metadata.name,
            bundleIdentifier: metadata.bundleIdentifier,
            format: metadata.format,
            currentVersion: metadata.version,
            path: metadata.url.path,
            vendorName: metadata.vendorName
        )

        // Initial version record
        let initialVersion = PluginVersion(version: metadata.version)
        plugin.versionHistory.append(initialVersion)

        // Assign vendor
        plugin.vendor = findOrCreateVendor(name: metadata.vendorName, cache: &vendorCache)

        modelContext.insert(plugin)
    }

    private func markRemovedPlugins(
        existingPlugins: [Plugin],
        seenBundleIDs: Set<String>,
        changes: inout [PluginChange]
    ) -> Int {
        var removedCount = 0
        for plugin in existingPlugins {
            if !seenBundleIDs.contains(plugin.bundleIdentifier) && !plugin.isRemoved {
                plugin.isRemoved = true
                removedCount += 1
                changes.append(PluginChange(
                    pluginName: plugin.name,
                    bundleIdentifier: plugin.bundleIdentifier,
                    changeType: .removed
                ))
            }
        }
        return removedCount
    }

    private func findOrCreateVendor(name: String, cache: inout [String: VendorInfo]) -> VendorInfo {
        if let existing = cache[name] {
            return existing
        }
        let vendor = VendorInfo(name: name)
        modelContext.insert(vendor)
        cache[name] = vendor
        return vendor
    }
}
