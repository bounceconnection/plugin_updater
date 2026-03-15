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
        // Deduplicate by (bundleIdentifier, format) — when the same plugin
        // format exists in both system and user directories, keep the one
        // with the newer version. Different formats (VST3, AU, CLAP) of the
        // same plugin are tracked separately.
        var dedupedByKey: [String: PluginMetadata] = [:]
        for metadata in scannedPlugins {
            let key = "\(metadata.bundleIdentifier):\(metadata.format.rawValue)"
            if let existing = dedupedByKey[key] {
                if metadata.version.isNewerVersion(than: existing.version) {
                    dedupedByKey[key] = metadata
                }
            } else {
                dedupedByKey[key] = metadata
            }
        }
        let uniquePlugins = Array(dedupedByKey.values)

        // Fetch all existing plugins
        let descriptor = FetchDescriptor<Plugin>()
        let existingPlugins = try modelContext.fetch(descriptor)

        // Index existing plugins by (bundleIdentifier, format) for O(1) lookup
        var existingByKey: [String: Plugin] = [:]
        for plugin in existingPlugins {
            let key = "\(plugin.bundleIdentifier):\(plugin.format.rawValue)"
            existingByKey[key] = plugin
        }

        // Build vendor cache from existing records
        let vendorDescriptor = FetchDescriptor<VendorInfo>()
        let existingVendors = try modelContext.fetch(vendorDescriptor)
        var vendorsByName: [String: VendorInfo] = [:]
        for vendor in existingVendors {
            vendorsByName[vendor.name] = vendor
        }

        var seenKeys: Set<String> = []
        var newCount = 0
        var updatedCount = 0
        var unchangedCount = 0
        var changes: [PluginChange] = []

        for metadata in uniquePlugins {
            let key = "\(metadata.bundleIdentifier):\(metadata.format.rawValue)"
            seenKeys.insert(key)

            if let existing = existingByKey[key] {
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
                seenKeys: seenKeys,
                changes: &changes
            )
        }

        // Normalize vendor names across formats (e.g., AU "Plugin Alliance" vs VST3 "Plugin-alliance")
        try normalizeVendorNames(vendorCache: &vendorsByName)

        // Normalize vendor names globally across all plugins from the same vendor
        // (e.g., VST3-only "bx_refinement" with "Plugin-alliance" when other PA plugins resolved to "Plugin Alliance")
        try normalizeVendorNamesGlobally(vendorCache: &vendorsByName)

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
        existing.architectures = metadata.architectures
        existing.fileSize = metadata.fileSize
        existing.fileCreationDate = metadata.fileCreationDate

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

        plugin.architectures = metadata.architectures
        plugin.fileSize = metadata.fileSize
        plugin.fileCreationDate = metadata.fileCreationDate

        // Initial version record
        let initialVersion = PluginVersion(version: metadata.version)
        plugin.versionHistory.append(initialVersion)

        // Assign vendor
        plugin.vendor = findOrCreateVendor(name: metadata.vendorName, cache: &vendorCache)

        modelContext.insert(plugin)
    }

    private func markRemovedPlugins(
        existingPlugins: [Plugin],
        seenKeys: Set<String>,
        changes: inout [PluginChange]
    ) -> Int {
        var removedCount = 0
        for plugin in existingPlugins {
            let key = "\(plugin.bundleIdentifier):\(plugin.format.rawValue)"
            if !seenKeys.contains(key) && !plugin.isRemoved {
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

    /// When the same plugin exists in multiple formats (VST3, AU, CLAP), the vendor name
    /// may differ because AU metadata (AudioComponents) is richer than VST3's fallback to
    /// bundle ID domain extraction. This normalizes all formats to use the best vendor name.
    private func normalizeVendorNames(vendorCache: inout [String: VendorInfo]) throws {
        let descriptor = FetchDescriptor<Plugin>(predicate: #Predicate { !$0.isRemoved })
        let allPlugins = try modelContext.fetch(descriptor)

        // Group by bundleIdentifier
        var byBundleID: [String: [Plugin]] = [:]
        for plugin in allPlugins {
            byBundleID[plugin.bundleIdentifier, default: []].append(plugin)
        }

        for (_, group) in byBundleID {
            guard group.count > 1 else { continue }

            let vendorNames = Set(group.map(\.vendorName))
            guard vendorNames.count > 1 else { continue }

            let bestName = pickBestVendorName(from: Array(vendorNames))
            let vendor = findOrCreateVendor(name: bestName, cache: &vendorCache)
            for plugin in group where plugin.vendorName != bestName {
                plugin.vendorName = bestName
                plugin.vendor = vendor
            }
        }
    }

    /// Scores vendor name candidates and picks the highest quality one.
    /// Prefers: longer names, mixed case (proper branding), spaces over hyphens.
    private func pickBestVendorName(from names: [String]) -> String {
        names.max { a, b in
            vendorNameScore(a) < vendorNameScore(b)
        } ?? names[0]
    }

    private func vendorNameScore(_ name: String) -> Int {
        var score = name.count
        if name == "Unknown" { score -= 100 }
        // Hyphens suggest bundle ID domain extraction (e.g., "Plugin-alliance")
        if name.contains("-") { score -= 5 }
        // Spaces suggest a proper display name (e.g., "Plugin Alliance")
        if name.contains(" ") { score += 5 }
        // Internal uppercase suggests proper branding (e.g., "LiquidSonics" vs "Liquidsonics")
        if name.dropFirst().contains(where: { $0.isUppercase }) { score += 10 }
        // Trailing year is noise from copyright extraction (e.g., "Rob Papen 2021")
        if name.range(of: #"\s\d{4}$"#, options: .regularExpression) != nil { score -= 20 }
        return score
    }

    /// Second normalization pass: groups all vendor names that are the same vendor
    /// but spelled differently (e.g., "Plugin-alliance" vs "Plugin Alliance") by comparing
    /// a canonical form (lowercased, hyphens→spaces). Picks the best spelling and applies
    /// it to all plugins, even single-format ones.
    private func normalizeVendorNamesGlobally(vendorCache: inout [String: VendorInfo]) throws {
        let descriptor = FetchDescriptor<Plugin>(predicate: #Predicate { !$0.isRemoved })
        let allPlugins = try modelContext.fetch(descriptor)

        // Collect unique vendor names and group by canonical form
        var namesByCanonical: [String: Set<String>] = [:]
        for plugin in allPlugins {
            let canonical = plugin.vendorName
                .lowercased()
                .replacingOccurrences(of: "-", with: " ")
            namesByCanonical[canonical, default: []].insert(plugin.vendorName)
        }

        // For each group with multiple spellings, pick the best and normalize
        for (_, variants) in namesByCanonical {
            guard variants.count > 1 else { continue }

            let bestName = pickBestVendorName(from: Array(variants))
            let vendor = findOrCreateVendor(name: bestName, cache: &vendorCache)
            for plugin in allPlugins where plugin.vendorName != bestName {
                let canonical = plugin.vendorName
                    .lowercased()
                    .replacingOccurrences(of: "-", with: " ")
                let bestCanonical = bestName
                    .lowercased()
                    .replacingOccurrences(of: "-", with: " ")
                if canonical == bestCanonical {
                    plugin.vendorName = bestName
                    plugin.vendor = vendor
                }
            }
        }
    }
}
