import Testing
import Foundation
import SwiftData
@testable import PluginUpdater

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
            parentDirectory: "VST3"
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
}
