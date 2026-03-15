import Testing
import Foundation
import SwiftData
@testable import Pluginventory

@Suite("PluginReconciler Tests")
struct PluginReconcilerTests {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    private func makeMetadata(
        name: String = "TestPlugin",
        bundleID: String = "com.test.plugin",
        version: String = "1.0.0",
        format: PluginFormat = .vst3,
        vendor: String = "TestVendor"
    ) -> PluginMetadata {
        PluginMetadata(
            url: URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3/\(name).vst3"),
            format: format,
            name: name,
            bundleIdentifier: bundleID,
            version: version,
            vendorName: vendor,
            audioComponentName: nil,
            copyright: nil,
            getInfoString: nil,
            bundleIDDomain: nil,
            parentDirectory: "VST3",
            plistFields: [:],
            architectures: [.arm64, .x86_64],
            fileSize: 1024,
            fileCreationDate: nil
        )
    }

    @Test("Detects new plugins and creates version history")
    func detectsNewPlugins() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        let scanned = [
            makeMetadata(name: "Synth1", bundleID: "com.test.synth1", version: "2.0.0"),
            makeMetadata(name: "EQ1", bundleID: "com.test.eq1", version: "1.5.0", format: .au),
        ]

        let result = try await reconciler.reconcile(scannedPlugins: scanned)

        #expect(result.newPlugins == 2)
        #expect(result.updatedPlugins == 0)
        #expect(result.removedPlugins == 0)
        #expect(result.totalProcessed == 2)
        #expect(result.changes.count == 2)
        #expect(result.changes.allSatisfy {
            if case .added = $0.changeType { return true }
            return false
        })

        // Verify records persisted
        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 2)

        // Verify initial version history was created
        let versions = try context.fetch(FetchDescriptor<PluginVersion>())
        #expect(versions.count == 2)
    }

    @Test("Detects version updates and records history")
    func detectsVersionUpdates() async throws {
        let container = try makeContainer()

        // Pre-populate a plugin at version 1.0.0
        let context = ModelContext(container)
        let existing = Plugin(
            name: "Synth1",
            bundleIdentifier: "com.test.synth1",
            format: .vst3,
            currentVersion: "1.0.0",
            path: "/Library/Audio/Plug-Ins/VST3/Synth1.vst3",
            vendorName: "TestVendor"
        )
        context.insert(existing)
        try context.save()

        // Scan shows version 2.0.0
        let reconciler = PluginReconciler(modelContainer: container)
        let scanned = [makeMetadata(name: "Synth1", bundleID: "com.test.synth1", version: "2.0.0")]
        let result = try await reconciler.reconcile(scannedPlugins: scanned)

        #expect(result.newPlugins == 0)
        #expect(result.updatedPlugins == 1)
        #expect(result.unchangedPlugins == 0)

        // Verify the change details
        let updateChange = result.changes.first {
            if case .updated = $0.changeType { return true }
            return false
        }
        #expect(updateChange != nil)
        if case .updated(let old, let new) = updateChange?.changeType {
            #expect(old == "1.0.0")
            #expect(new == "2.0.0")
        }

        // Verify version history was appended
        let freshContext = ModelContext(container)
        let plugins = try freshContext.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.first?.currentVersion == "2.0.0")
        #expect(plugins.first?.versionHistory.count == 1)
        #expect(plugins.first?.versionHistory.first?.previousVersion == "1.0.0")
    }

    @Test("Soft-deletes removed plugins")
    func softDeletesRemovedPlugins() async throws {
        let container = try makeContainer()

        // Pre-populate two plugins
        let context = ModelContext(container)
        let plugin1 = Plugin(
            name: "Synth1", bundleIdentifier: "com.test.synth1",
            format: .vst3, currentVersion: "1.0.0",
            path: "/Library/Audio/Plug-Ins/VST3/Synth1.vst3"
        )
        let plugin2 = Plugin(
            name: "EQ1", bundleIdentifier: "com.test.eq1",
            format: .au, currentVersion: "1.0.0",
            path: "/Library/Audio/Plug-Ins/Components/EQ1.component"
        )
        context.insert(plugin1)
        context.insert(plugin2)
        try context.save()

        // Scan only finds plugin1 — plugin2 should be marked removed
        let reconciler = PluginReconciler(modelContainer: container)
        let scanned = [makeMetadata(name: "Synth1", bundleID: "com.test.synth1", version: "1.0.0")]
        let result = try await reconciler.reconcile(scannedPlugins: scanned)

        #expect(result.removedPlugins == 1)
        #expect(result.unchangedPlugins == 1)

        let removeChange = result.changes.first {
            if case .removed = $0.changeType { return true }
            return false
        }
        #expect(removeChange?.pluginName == "EQ1")

        // Verify soft-delete — record still exists but isRemoved = true
        let freshContext = ModelContext(container)
        let allPlugins = try freshContext.fetch(FetchDescriptor<Plugin>())
        #expect(allPlugins.count == 2) // not hard-deleted
        let removed = allPlugins.first { $0.bundleIdentifier == "com.test.eq1" }
        #expect(removed?.isRemoved == true)
    }

    @Test("Detects reappeared plugins")
    func detectsReappearedPlugins() async throws {
        let container = try makeContainer()

        // Pre-populate a removed plugin
        let context = ModelContext(container)
        let plugin = Plugin(
            name: "Synth1", bundleIdentifier: "com.test.synth1",
            format: .vst3, currentVersion: "1.0.0",
            path: "/Library/Audio/Plug-Ins/VST3/Synth1.vst3",
            isRemoved: true
        )
        context.insert(plugin)
        try context.save()

        // Scan finds the plugin again
        let reconciler = PluginReconciler(modelContainer: container)
        let scanned = [makeMetadata(name: "Synth1", bundleID: "com.test.synth1", version: "1.0.0")]
        let result = try await reconciler.reconcile(scannedPlugins: scanned)

        let reappearChange = result.changes.first {
            if case .reappeared = $0.changeType { return true }
            return false
        }
        #expect(reappearChange != nil)

        // Verify isRemoved is now false
        let freshContext = ModelContext(container)
        let plugins = try freshContext.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.first?.isRemoved == false)
    }

    @Test("Creates and reuses VendorInfo records")
    func vendorCreationAndReuse() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // Two plugins from the same vendor
        let scanned = [
            makeMetadata(name: "Synth1", bundleID: "com.fab.synth1", vendor: "FabFilter"),
            makeMetadata(name: "EQ1", bundleID: "com.fab.eq1", vendor: "FabFilter"),
            makeMetadata(name: "Comp1", bundleID: "com.waves.comp1", vendor: "Waves"),
        ]

        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        // Should have exactly 2 vendor records, not 3
        let context = ModelContext(container)
        let vendors = try context.fetch(FetchDescriptor<VendorInfo>())
        #expect(vendors.count == 2)

        let fabfilter = vendors.first { $0.name == "FabFilter" }
        #expect(fabfilter?.plugins.count == 2)
    }

    @Test("Handles empty scan gracefully")
    func emptyScan() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        let result = try await reconciler.reconcile(scannedPlugins: [])

        #expect(result.newPlugins == 0)
        #expect(result.updatedPlugins == 0)
        #expect(result.removedPlugins == 0)
        #expect(result.totalProcessed == 0)
        #expect(result.changes.isEmpty)
    }

    @Test("Same plugin in multiple formats is tracked separately")
    func multiFormatPluginsTrackedSeparately() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        let scanned = [
            makeMetadata(name: "PaulXStretch", bundleID: "com.sonosaurus.paulxstretch", version: "1.6.0", format: .vst3),
            makeMetadata(name: "PaulXStretch", bundleID: "com.sonosaurus.paulxstretch", version: "1.6.0", format: .au, vendor: "Sonosaurus"),
        ]

        let result = try await reconciler.reconcile(scannedPlugins: scanned)

        #expect(result.newPlugins == 2)
        #expect(result.totalProcessed == 2)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 2)

        let formats = Set(plugins.map(\.format))
        #expect(formats.contains(.vst3))
        #expect(formats.contains(.au))
    }

    @Test("Removing one format does not remove others with same bundle ID")
    func removeOneFormatKeepsOthers() async throws {
        let container = try makeContainer()

        // Pre-populate both VST3 and AU
        let context = ModelContext(container)
        let vst3 = Plugin(
            name: "PaulXStretch", bundleIdentifier: "com.sonosaurus.paulxstretch",
            format: .vst3, currentVersion: "1.6.0",
            path: "/Library/Audio/Plug-Ins/VST3/PaulXStretch.vst3"
        )
        let au = Plugin(
            name: "PaulXStretch", bundleIdentifier: "com.sonosaurus.paulxstretch",
            format: .au, currentVersion: "1.6.0",
            path: "/Library/Audio/Plug-Ins/Components/PaulXStretch.component"
        )
        context.insert(vst3)
        context.insert(au)
        try context.save()

        // Scan only finds the VST3 — AU should be marked removed
        let reconciler = PluginReconciler(modelContainer: container)
        let scanned = [
            makeMetadata(name: "PaulXStretch", bundleID: "com.sonosaurus.paulxstretch", version: "1.6.0", format: .vst3),
        ]
        let result = try await reconciler.reconcile(scannedPlugins: scanned)

        #expect(result.removedPlugins == 1)
        #expect(result.unchangedPlugins == 1)

        let freshContext = ModelContext(container)
        let plugins = try freshContext.fetch(FetchDescriptor<Plugin>())
        let removedAU = plugins.first { $0.format == .au }
        let keptVST3 = plugins.first { $0.format == .vst3 }
        #expect(removedAU?.isRemoved == true)
        #expect(keptVST3?.isRemoved == false)
    }

    @Test("Unchanged plugins update lastSeenDate only")
    func unchangedPluginsUpdateLastSeen() async throws {
        let container = try makeContainer()

        let context = ModelContext(container)
        let oldDate = Date.distantPast
        let plugin = Plugin(
            name: "Synth1", bundleIdentifier: "com.test.synth1",
            format: .vst3, currentVersion: "1.0.0",
            path: "/Library/Audio/Plug-Ins/VST3/Synth1.vst3",
            lastSeenDate: oldDate
        )
        context.insert(plugin)
        try context.save()

        let reconciler = PluginReconciler(modelContainer: container)
        let scanned = [makeMetadata(name: "Synth1", bundleID: "com.test.synth1", version: "1.0.0")]
        let result = try await reconciler.reconcile(scannedPlugins: scanned)

        #expect(result.unchangedPlugins == 1)
        #expect(result.updatedPlugins == 0)

        let freshContext = ModelContext(container)
        let plugins = try freshContext.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.first!.lastSeenDate > oldDate)
    }

    // MARK: - Vendor Name Normalization

    @Test("Normalizes hyphenated domain name to spaced display name")
    func normalizesHyphenatedToSpaced() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // Real-world: AU gets "Plugin Alliance" from AudioComponents,
        // VST3 gets "Plugin-alliance" from bundle ID domain extraction
        let scanned = [
            makeMetadata(name: "bx_solo", bundleID: "com.plugin-alliance.bx_solo", version: "1.16.1", format: .au, vendor: "Plugin Alliance"),
            makeMetadata(name: "bx_solo", bundleID: "com.plugin-alliance.bx_solo", version: "1.16.1", format: .vst3, vendor: "Plugin-alliance"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 2)
        #expect(plugins.allSatisfy { $0.vendorName == "Plugin Alliance" })
    }

    @Test("Normalizes truncated name to full name")
    func normalizesTruncatedToFull() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // Real-world: AU gets "Minimal Audio", VST3 only resolves "Minimal" from domain
        let scanned = [
            makeMetadata(name: "Cluster Delay", bundleID: "com.minimal-audio.cluster-delay", version: "1.3.0", format: .au, vendor: "Minimal Audio"),
            makeMetadata(name: "Cluster Delay", bundleID: "com.minimal-audio.cluster-delay", version: "1.3.0", format: .vst3, vendor: "Minimal"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.allSatisfy { $0.vendorName == "Minimal Audio" })
    }

    @Test("Normalizes flat casing to proper brand casing")
    func normalizesFlatToProperCase() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // Real-world: AU gets "LiquidSonics" from AudioComponents,
        // VST3 gets "Liquidsonics" from capitalized domain
        let scanned = [
            makeMetadata(name: "Cinematic Rooms", bundleID: "com.liquidsonics.cinematic-rooms", version: "1.3.9", format: .au, vendor: "LiquidSonics"),
            makeMetadata(name: "Cinematic Rooms", bundleID: "com.liquidsonics.cinematic-rooms", version: "1.3.9", format: .vst3, vendor: "Liquidsonics"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.allSatisfy { $0.vendorName == "LiquidSonics" })
    }

    @Test("Normalization skips plugins with only one format")
    func normalizationSkipsSingleFormat() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        let scanned = [
            makeMetadata(name: "PluginA", bundleID: "com.test.a", version: "1.0", format: .vst3, vendor: "Some-vendor"),
            makeMetadata(name: "PluginB", bundleID: "com.test.b", version: "1.0", format: .au, vendor: "Other Vendor"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        let pluginA = plugins.first { $0.bundleIdentifier == "com.test.a" }
        let pluginB = plugins.first { $0.bundleIdentifier == "com.test.b" }
        // Names left untouched — no cross-format conflict to resolve
        #expect(pluginA?.vendorName == "Some-vendor")
        #expect(pluginB?.vendorName == "Other Vendor")
    }

    @Test("Normalization skips when all formats already agree")
    func normalizationSkipsWhenConsistent() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        let scanned = [
            makeMetadata(name: "Pro-Q 3", bundleID: "com.fabfilter.Pro-Q.3", version: "3.23", format: .au, vendor: "FabFilter"),
            makeMetadata(name: "Pro-Q 3", bundleID: "com.fabfilter.Pro-Q.3", version: "3.23", format: .vst3, vendor: "FabFilter"),
            makeMetadata(name: "Pro-Q 3", bundleID: "com.fabfilter.Pro-Q.3", version: "3.23", format: .clap, vendor: "FabFilter"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 3)
        #expect(plugins.allSatisfy { $0.vendorName == "FabFilter" })
    }

    @Test("Normalization picks best name across three formats")
    func normalizesAcrossThreeFormats() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        let scanned = [
            makeMetadata(name: "bx_cleansweep V2", bundleID: "com.plugin-alliance.bx_cleansweep", version: "2.16.1", format: .au, vendor: "Plugin Alliance"),
            makeMetadata(name: "bx_cleansweep V2", bundleID: "com.plugin-alliance.bx_cleansweep", version: "2.16.1", format: .vst3, vendor: "Plugin-alliance"),
            makeMetadata(name: "bx_cleansweep V2", bundleID: "com.plugin-alliance.bx_cleansweep", version: "2.16.1", format: .clap, vendor: "Plugin-alliance"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 3)
        #expect(plugins.allSatisfy { $0.vendorName == "Plugin Alliance" })
    }

    @Test("Normalization prefers any name over Unknown")
    func normalizationPrefersOverUnknown() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        let scanned = [
            makeMetadata(name: "Mystery Plugin", bundleID: "com.mystery.plugin", version: "1.0", format: .au, vendor: "Mystery"),
            makeMetadata(name: "Mystery Plugin", bundleID: "com.mystery.plugin", version: "1.0", format: .vst3, vendor: "Unknown"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.allSatisfy { $0.vendorName == "Mystery" })
    }

    @Test("Normalization updates VendorInfo relationship")
    func normalizationUpdatesVendorRelationship() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        let scanned = [
            makeMetadata(name: "bx_saturator V2", bundleID: "com.plugin-alliance.bx_saturator", version: "2.12.1", format: .au, vendor: "Plugin Alliance"),
            makeMetadata(name: "bx_saturator V2", bundleID: "com.plugin-alliance.bx_saturator", version: "2.12.1", format: .vst3, vendor: "Plugin-alliance"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())

        // Both plugins should point to the same VendorInfo record
        let vendors = Set(plugins.compactMap { $0.vendor?.name })
        #expect(vendors.count == 1)
        #expect(vendors.first == "Plugin Alliance")
    }

    @Test("Normalization does not affect removed plugins")
    func normalizationIgnoresRemovedPlugins() async throws {
        let container = try makeContainer()

        // Pre-populate a removed plugin with the "wrong" vendor name
        let context = ModelContext(container)
        let removed = Plugin(
            name: "bx_solo", bundleIdentifier: "com.plugin-alliance.bx_solo",
            format: .clap, currentVersion: "1.16.1",
            path: "/Library/Audio/Plug-Ins/CLAP/bx_solo.clap",
            vendorName: "Plugin-alliance",
            isRemoved: true
        )
        context.insert(removed)
        try context.save()

        // Scan only has AU and VST3 (CLAP was uninstalled)
        let reconciler = PluginReconciler(modelContainer: container)
        let scanned = [
            makeMetadata(name: "bx_solo", bundleID: "com.plugin-alliance.bx_solo", version: "1.16.1", format: .au, vendor: "Plugin Alliance"),
            makeMetadata(name: "bx_solo", bundleID: "com.plugin-alliance.bx_solo", version: "1.16.1", format: .vst3, vendor: "Plugin-alliance"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let freshContext = ModelContext(container)
        let allPlugins = try freshContext.fetch(FetchDescriptor<Plugin>())
        let active = allPlugins.filter { !$0.isRemoved }
        let removedPlugin = allPlugins.first { $0.isRemoved }

        // Active plugins normalized
        #expect(active.allSatisfy { $0.vendorName == "Plugin Alliance" })
        // Removed plugin untouched (normalization only queries non-removed)
        #expect(removedPlugin?.vendorName == "Plugin-alliance")
    }

    @Test("Normalization works on subsequent scans with pre-existing plugins")
    func normalizationOnSubsequentScan() async throws {
        let container = try makeContainer()

        // First scan: only VST3 was installed, got the "bad" name
        let context = ModelContext(container)
        let existing = Plugin(
            name: "bx_refinement", bundleIdentifier: "com.plugin-alliance.bx_refinement",
            format: .vst3, currentVersion: "1.12.1",
            path: "/Library/Audio/Plug-Ins/VST3/bx_refinement.vst3",
            vendorName: "Plugin-alliance"
        )
        context.insert(existing)
        try context.save()

        // Second scan: user also installed AU format
        let reconciler = PluginReconciler(modelContainer: container)
        let scanned = [
            makeMetadata(name: "bx_refinement", bundleID: "com.plugin-alliance.bx_refinement", version: "1.12.1", format: .au, vendor: "Plugin Alliance"),
            makeMetadata(name: "bx_refinement", bundleID: "com.plugin-alliance.bx_refinement", version: "1.12.1", format: .vst3, vendor: "Plugin-alliance"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let freshContext = ModelContext(container)
        let plugins = try freshContext.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 2)
        // Both should now be normalized
        #expect(plugins.allSatisfy { $0.vendorName == "Plugin Alliance" })
    }

    @Test("Normalization prefers name without trailing year")
    func normalizationPrefersNameWithoutYear() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // Real-world: AU gets "Rob Papen" from AudioComponents,
        // VST3 gets "Rob Papen 2021" from copyright with trailing year
        let scanned = [
            makeMetadata(name: "RP-Verb2", bundleID: "com.robpapen.rp-verb2", version: "1.0.1", format: .au, vendor: "Rob Papen"),
            makeMetadata(name: "RP-Verb2", bundleID: "com.robpapen.rp-verb2", version: "1.0.1", format: .vst3, vendor: "Rob Papen 2021"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 2)
        #expect(plugins.allSatisfy { $0.vendorName == "Rob Papen" })
    }

    @Test("Normalization handles multiple year variants from same vendor")
    func normalizationHandlesMultipleYearVariants() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // Some Rob Papen plugins only exist in one format with different year suffixes
        // Cross-bundle normalization doesn't apply here, but the VendorResolver fix
        // should strip years at extraction time. This test verifies the scoring
        // for plugins that DO have both formats.
        let scanned = [
            makeMetadata(name: "RP-Delay", bundleID: "com.robpapen.rp-delay", version: "1.0.3", format: .au, vendor: "Rob Papen"),
            makeMetadata(name: "RP-Delay", bundleID: "com.robpapen.rp-delay", version: "1.0.3", format: .vst3, vendor: "Rob Papen 2021"),
            makeMetadata(name: "RP-Distort2", bundleID: "com.robpapen.rp-distort2", version: "1.0.0", format: .au, vendor: "Rob Papen"),
            makeMetadata(name: "RP-Distort2", bundleID: "com.robpapen.rp-distort2", version: "1.0.0", format: .vst3, vendor: "Rob Papen 2022"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 4)
        #expect(plugins.allSatisfy { $0.vendorName == "Rob Papen" })
    }

    @Test("Normalization picks year-free name even when it is shorter")
    func normalizationPicksYearFreeOverLonger() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // "Rob Papen 2025" is longer than "Rob Papen" but worse due to year suffix
        let scanned = [
            makeMetadata(name: "WirePluck", bundleID: "com.robpapen.wirepluck", version: "1.0.1", format: .au, vendor: "Rob Papen 2025"),
            makeMetadata(name: "WirePluck", bundleID: "com.robpapen.wirepluck", version: "1.0.1", format: .vst3, vendor: "Rob Papen"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.allSatisfy { $0.vendorName == "Rob Papen" })
    }

    @Test("Normalization between two year variants picks either consistently")
    func normalizationBetweenTwoYearVariants() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // Both have year suffixes — neither is ideal but they should at least agree
        let scanned = [
            makeMetadata(name: "Predator3", bundleID: "com.robpapen.predator3", version: "1.0.2", format: .au, vendor: "Rob Papen 2021"),
            makeMetadata(name: "Predator3", bundleID: "com.robpapen.predator3", version: "1.0.2", format: .vst3, vendor: "Rob Papen 2021"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        // Both have the same name — no normalization needed, but should not crash
        let vendorNames = Set(plugins.map(\.vendorName))
        #expect(vendorNames.count == 1)
    }

    @Test("Normalization with pre-existing year-suffixed vendor gets corrected on rescan")
    func normalizationCorrectsPreviouslyStoredYearSuffix() async throws {
        let container = try makeContainer()

        // Simulate a plugin stored with old year-suffixed name from a prior scan
        let context = ModelContext(container)
        let existing = Plugin(
            name: "RP-AMod", bundleIdentifier: "com.robpapen.rp-amod",
            format: .vst3, currentVersion: "1.0.1",
            path: "/Library/Audio/Plug-Ins/VST3/Rob Papen/RP-AMod.vst3",
            vendorName: "Rob Papen 2021"
        )
        context.insert(existing)
        try context.save()

        // New scan: AU format now present with clean name
        let reconciler = PluginReconciler(modelContainer: container)
        let scanned = [
            makeMetadata(name: "RP-AMod", bundleID: "com.robpapen.rp-amod", version: "1.0.1", format: .au, vendor: "Rob Papen"),
            makeMetadata(name: "RP-AMod", bundleID: "com.robpapen.rp-amod", version: "1.0.1", format: .vst3, vendor: "Rob Papen 2021"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let freshContext = ModelContext(container)
        let plugins = try freshContext.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 2)
        #expect(plugins.allSatisfy { $0.vendorName == "Rob Papen" })
    }

    @Test("Normalization year penalty does not affect names with non-trailing digits")
    func normalizationYearPenaltyOnlyAppliesToTrailingYear() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // "D16 Group" has digits in the name but not a trailing year
        let scanned = [
            makeMetadata(name: "Devastor2", bundleID: "com.d16group.devastor2", version: "2.3.2", format: .au, vendor: "D16 Group Audio Software"),
            makeMetadata(name: "Devastor2", bundleID: "com.d16group.devastor2", version: "2.3.2", format: .vst3, vendor: "D16"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        // Longer, more complete name should win (no year penalty applied)
        #expect(plugins.allSatisfy { $0.vendorName == "D16 Group Audio Software" })
    }

    // MARK: - Global Vendor Name Normalization

    @Test("Global normalization fixes VST3-only plugins from same vendor")
    func globalNormalizationFixesVST3Only() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // bx_solo has both formats → per-bundleID normalization picks "Plugin Alliance"
        // bx_refinement is VST3-only → global normalization should fix it too
        let scanned = [
            makeMetadata(name: "bx_solo", bundleID: "com.plugin-alliance.bx_solo", version: "1.16.1", format: .au, vendor: "Plugin Alliance"),
            makeMetadata(name: "bx_solo", bundleID: "com.plugin-alliance.bx_solo", version: "1.16.1", format: .vst3, vendor: "Plugin-alliance"),
            makeMetadata(name: "bx_refinement", bundleID: "com.plugin-alliance.bx_refinement", version: "1.12.1", format: .vst3, vendor: "Plugin-alliance"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 3)
        #expect(plugins.allSatisfy { $0.vendorName == "Plugin Alliance" })
    }

    @Test("Global normalization fixes multiple VST3-only plugins")
    func globalNormalizationFixesMultipleVST3Only() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // One plugin with both formats provides the "good" name,
        // several VST3-only plugins should all get normalized
        let scanned = [
            makeMetadata(name: "bx_cleansweep V2", bundleID: "com.plugin-alliance.bx_cleansweep", version: "2.16.1", format: .au, vendor: "Plugin Alliance"),
            makeMetadata(name: "bx_cleansweep V2", bundleID: "com.plugin-alliance.bx_cleansweep", version: "2.16.1", format: .vst3, vendor: "Plugin-alliance"),
            makeMetadata(name: "SPL Transient Designer Plus", bundleID: "com.plugin-alliance.spl-td-plus", version: "1.11.0", format: .vst3, vendor: "Plugin-alliance"),
            makeMetadata(name: "SPL Free Ranger", bundleID: "com.plugin-alliance.spl-fr", version: "1.18.1", format: .vst3, vendor: "Plugin-alliance"),
            makeMetadata(name: "SPL IRON", bundleID: "com.plugin-alliance.spl-iron", version: "1.7.0", format: .vst3, vendor: "Plugin-alliance"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 5)
        #expect(plugins.allSatisfy { $0.vendorName == "Plugin Alliance" })
    }

    @Test("Global normalization does not merge different vendors")
    func globalNormalizationDoesNotMergeDifferentVendors() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // "Plugin Alliance" and "Plugin Boutique" are different vendors
        let scanned = [
            makeMetadata(name: "bx_solo", bundleID: "com.plugin-alliance.bx_solo", version: "1.16.1", format: .au, vendor: "Plugin Alliance"),
            makeMetadata(name: "Scaler2", bundleID: "com.pluginboutique.scaler2", version: "2.7.3", format: .au, vendor: "Plugin Boutique"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        let alliance = plugins.first { $0.bundleIdentifier == "com.plugin-alliance.bx_solo" }
        let boutique = plugins.first { $0.bundleIdentifier == "com.pluginboutique.scaler2" }
        #expect(alliance?.vendorName == "Plugin Alliance")
        #expect(boutique?.vendorName == "Plugin Boutique")
    }

    @Test("Global normalization handles all-VST3 vendor with no AU reference")
    func globalNormalizationAllVST3SameVendor() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        // All VST3-only, all "Plugin-alliance" — no better name available
        // Global normalization should leave them alone (nothing to improve)
        let scanned = [
            makeMetadata(name: "PluginA", bundleID: "com.plugin-alliance.a", version: "1.0", format: .vst3, vendor: "Plugin-alliance"),
            makeMetadata(name: "PluginB", bundleID: "com.plugin-alliance.b", version: "1.0", format: .vst3, vendor: "Plugin-alliance"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        // All same vendor name — no global normalization triggered
        let vendorNames = Set(plugins.map(\.vendorName))
        #expect(vendorNames.count == 1)
        #expect(vendorNames.first == "Plugin-alliance")
    }

    @Test("Global normalization updates VendorInfo for single-format plugins")
    func globalNormalizationUpdatesVendorInfo() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        let scanned = [
            makeMetadata(name: "elysia niveau filter", bundleID: "com.plugin-alliance.elysia-niveau", version: "1.16.1", format: .au, vendor: "Plugin Alliance"),
            makeMetadata(name: "Shadow Hills Comp", bundleID: "com.plugin-alliance.shadow-hills", version: "1.5.0", format: .vst3, vendor: "Plugin-alliance"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        // Both should share the same VendorInfo record
        let vendorInfoNames = Set(plugins.compactMap { $0.vendor?.name })
        #expect(vendorInfoNames.count == 1)
        #expect(vendorInfoNames.first == "Plugin Alliance")
    }
}
