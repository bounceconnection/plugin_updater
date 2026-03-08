import Testing
import Foundation
import SwiftData
@testable import PluginUpdater

@Suite("Plugin Hide/Unhide Tests")
struct PluginHideTests {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    @Test("Plugin defaults to not hidden")
    func defaultIsHiddenFalse() {
        let plugin = Plugin(
            name: "Serum",
            bundleIdentifier: "com.xferrecords.Serum",
            format: .vst3,
            currentVersion: "1.35",
            path: "/Library/Audio/Plug-Ins/VST3/Serum.vst3"
        )
        #expect(plugin.isHidden == false)
    }

    @Test("Plugin can be hidden and unhidden")
    func hideAndUnhide() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugin = Plugin(
            name: "Serum",
            bundleIdentifier: "com.xferrecords.Serum",
            format: .vst3,
            currentVersion: "1.35",
            path: "/Library/Audio/Plug-Ins/VST3/Serum.vst3"
        )
        context.insert(plugin)
        try context.save()

        plugin.isHidden = true
        try context.save()

        let descriptor = FetchDescriptor<Plugin>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched[0].isHidden == true)

        // Unhide
        fetched[0].isHidden = false
        try context.save()

        let refetched = try context.fetch(descriptor)
        #expect(refetched[0].isHidden == false)
    }

    @Test("Hidden and visible plugins can be queried separately")
    func separateHiddenAndVisibleQuery() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let visible1 = Plugin(
            name: "Pro-Q 3",
            bundleIdentifier: "com.fabfilter.ProQ3",
            format: .vst3,
            currentVersion: "3.21",
            path: "/Library/Audio/Plug-Ins/VST3/FabFilter Pro-Q 3.vst3"
        )
        let visible2 = Plugin(
            name: "Kontakt",
            bundleIdentifier: "com.native-instruments.Kontakt7",
            format: .au,
            currentVersion: "7.5",
            path: "/Library/Audio/Plug-Ins/Components/Kontakt 7.component"
        )
        let hidden = Plugin(
            name: "OldPlugin",
            bundleIdentifier: "com.old.plugin",
            format: .clap,
            currentVersion: "1.0",
            path: "/Library/Audio/Plug-Ins/CLAP/OldPlugin.clap",
            isHidden: true
        )
        context.insert(visible1)
        context.insert(visible2)
        context.insert(hidden)
        try context.save()

        let visibleDescriptor = FetchDescriptor<Plugin>(
            predicate: #Predicate { !$0.isHidden && !$0.isRemoved }
        )
        let visiblePlugins = try context.fetch(visibleDescriptor)
        #expect(visiblePlugins.count == 2)
        #expect(visiblePlugins.allSatisfy { !$0.isHidden })

        let hiddenDescriptor = FetchDescriptor<Plugin>(
            predicate: #Predicate { $0.isHidden && !$0.isRemoved }
        )
        let hiddenPlugins = try context.fetch(hiddenDescriptor)
        #expect(hiddenPlugins.count == 1)
        #expect(hiddenPlugins[0].name == "OldPlugin")
    }

    @Test("isHidden is independent from isRemoved")
    func hiddenAndRemovedAreIndependent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugin = Plugin(
            name: "TestPlugin",
            bundleIdentifier: "com.test.plugin",
            format: .vst3,
            currentVersion: "1.0",
            path: "/Library/Audio/Plug-Ins/VST3/TestPlugin.vst3"
        )
        context.insert(plugin)
        try context.save()

        // Can be both hidden and removed independently
        plugin.isHidden = true
        plugin.isRemoved = true
        try context.save()

        let descriptor = FetchDescriptor<Plugin>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched[0].isHidden == true)
        #expect(fetched[0].isRemoved == true)
    }

    @Test("Plugin created with isHidden true persists correctly")
    func createHiddenPlugin() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugin = Plugin(
            name: "HiddenPlugin",
            bundleIdentifier: "com.hidden.plugin",
            format: .vst3,
            currentVersion: "2.0",
            path: "/Library/Audio/Plug-Ins/VST3/HiddenPlugin.vst3",
            isHidden: true
        )
        context.insert(plugin)
        try context.save()

        let descriptor = FetchDescriptor<Plugin>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched[0].isHidden == true)
        #expect(fetched[0].name == "HiddenPlugin")
    }

    @Test("Multiple plugins can be hidden at once")
    func hideMultiplePlugins() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugins = [
            Plugin(name: "Plugin A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3"),
            Plugin(name: "Plugin B", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component"),
            Plugin(name: "Plugin C", bundleIdentifier: "com.c", format: .clap, currentVersion: "1.0", path: "/c.clap"),
        ]
        for p in plugins { context.insert(p) }
        try context.save()

        // Hide all
        for p in plugins { p.isHidden = true }
        try context.save()

        let descriptor = FetchDescriptor<Plugin>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 3)
        #expect(fetched.allSatisfy { $0.isHidden })

        // Unhide one
        fetched.first { $0.bundleIdentifier == "com.b" }?.isHidden = false
        try context.save()

        let refetched = try context.fetch(descriptor)
        let hiddenCount = refetched.filter { $0.isHidden }.count
        #expect(hiddenCount == 2)
    }

    // MARK: - Reconciler preserves isHidden

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
            plistFields: [:]
        )
    }

    @Test("Reconciler preserves isHidden when plugin version updates")
    func reconcilerPreservesHiddenOnUpdate() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugin = Plugin(
            name: "HiddenSynth",
            bundleIdentifier: "com.test.hiddensynth",
            format: .vst3,
            currentVersion: "1.0.0",
            path: "/Library/Audio/Plug-Ins/VST3/HiddenSynth.vst3",
            isHidden: true
        )
        context.insert(plugin)
        try context.save()

        // Reconcile with a newer version
        let reconciler = PluginReconciler(modelContainer: container)
        let scanned = [makeMetadata(name: "HiddenSynth", bundleID: "com.test.hiddensynth", version: "2.0.0")]
        let result = try await reconciler.reconcile(scannedPlugins: scanned)

        #expect(result.updatedPlugins == 1)

        // isHidden must still be true after reconciliation
        let freshContext = ModelContext(container)
        let plugins = try freshContext.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.first?.isHidden == true)
        #expect(plugins.first?.currentVersion == "2.0.0")
    }

    @Test("Reconciler preserves isHidden when plugin reappears")
    func reconcilerPreservesHiddenOnReappear() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugin = Plugin(
            name: "HiddenSynth",
            bundleIdentifier: "com.test.hiddensynth",
            format: .vst3,
            currentVersion: "1.0.0",
            path: "/Library/Audio/Plug-Ins/VST3/HiddenSynth.vst3",
            isRemoved: true,
            isHidden: true
        )
        context.insert(plugin)
        try context.save()

        // Plugin reappears in scan
        let reconciler = PluginReconciler(modelContainer: container)
        let scanned = [makeMetadata(name: "HiddenSynth", bundleID: "com.test.hiddensynth", version: "1.0.0")]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let freshContext = ModelContext(container)
        let plugins = try freshContext.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.first?.isRemoved == false)
        #expect(plugins.first?.isHidden == true) // hidden status preserved
    }

    @Test("Reconciler preserves isHidden when plugin is soft-deleted")
    func reconcilerPreservesHiddenOnRemove() async throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugin = Plugin(
            name: "HiddenSynth",
            bundleIdentifier: "com.test.hiddensynth",
            format: .vst3,
            currentVersion: "1.0.0",
            path: "/Library/Audio/Plug-Ins/VST3/HiddenSynth.vst3",
            isHidden: true
        )
        context.insert(plugin)
        try context.save()

        // Empty scan — plugin disappears
        let reconciler = PluginReconciler(modelContainer: container)
        _ = try await reconciler.reconcile(scannedPlugins: [])

        let freshContext = ModelContext(container)
        let plugins = try freshContext.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.first?.isRemoved == true)
        #expect(plugins.first?.isHidden == true) // hidden status preserved
    }

    // MARK: - Dashboard filtering logic

    @Test("Hidden plugins excluded from visible count and format count")
    func hiddenExcludedFromCounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let visible1 = Plugin(name: "VST A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3")
        let visible2 = Plugin(name: "VST B", bundleIdentifier: "com.b", format: .vst3, currentVersion: "1.0", path: "/b.vst3")
        let hiddenVST = Plugin(name: "VST C", bundleIdentifier: "com.c", format: .vst3, currentVersion: "1.0", path: "/c.vst3", isHidden: true)
        let visibleAU = Plugin(name: "AU A", bundleIdentifier: "com.d", format: .au, currentVersion: "1.0", path: "/d.component")
        let removedPlugin = Plugin(name: "Removed", bundleIdentifier: "com.e", format: .vst3, currentVersion: "1.0", path: "/e.vst3", isRemoved: true)

        for p in [visible1, visible2, hiddenVST, visibleAU, removedPlugin] { context.insert(p) }
        try context.save()

        // Simulate DashboardView's query: !isRemoved
        let nonRemoved = FetchDescriptor<Plugin>(predicate: #Predicate { !$0.isRemoved })
        let plugins = try context.fetch(nonRemoved)

        // visibleCount: non-hidden among non-removed
        let visibleCount = plugins.filter { !$0.isHidden }.count
        #expect(visibleCount == 3) // VST A, VST B, AU A

        // hiddenCount: hidden among non-removed
        let hiddenCount = plugins.filter { $0.isHidden }.count
        #expect(hiddenCount == 1) // VST C

        // pluginCount(for: .vst3): non-hidden, non-removed, vst3
        let vst3Count = plugins.filter { !$0.isHidden && $0.format == .vst3 }.count
        #expect(vst3Count == 2) // VST A, VST B (not hidden VST C, not removed)

        let auCount = plugins.filter { !$0.isHidden && $0.format == .au }.count
        #expect(auCount == 1)
    }

    @Test("Hidden filter shows only hidden non-removed plugins")
    func hiddenFilterShowsOnlyHidden() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let visible = Plugin(name: "Visible", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3")
        let hidden = Plugin(name: "Hidden", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component", isHidden: true)
        let hiddenAndRemoved = Plugin(name: "HiddenRemoved", bundleIdentifier: "com.c", format: .clap, currentVersion: "1.0", path: "/c.clap", isRemoved: true, isHidden: true)

        for p in [visible, hidden, hiddenAndRemoved] { context.insert(p) }
        try context.save()

        // DashboardView sidebar .hidden filter: isHidden && !isRemoved
        let nonRemoved = FetchDescriptor<Plugin>(predicate: #Predicate { !$0.isRemoved })
        let plugins = try context.fetch(nonRemoved)
        let hiddenResults = plugins.filter { $0.isHidden }

        #expect(hiddenResults.count == 1)
        #expect(hiddenResults[0].name == "Hidden")
    }

    @Test("Search filtering respects hidden state")
    func searchRespectsHiddenState() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let visibleSerum = Plugin(name: "Serum", bundleIdentifier: "com.xfer.serum", format: .vst3, currentVersion: "1.35", path: "/serum.vst3")
        let hiddenSerum = Plugin(name: "Serum FX", bundleIdentifier: "com.xfer.serumfx", format: .vst3, currentVersion: "1.35", path: "/serumfx.vst3", isHidden: true)

        for p in [visibleSerum, hiddenSerum] { context.insert(p) }
        try context.save()

        let nonRemoved = FetchDescriptor<Plugin>(predicate: #Predicate { !$0.isRemoved })
        let plugins = try context.fetch(nonRemoved)

        // Simulate "All" sidebar + "Serum" search (dashboard filters out hidden first)
        let searchText = "Serum"
        let visibleResults = plugins
            .filter { !$0.isHidden }
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        #expect(visibleResults.count == 1)
        #expect(visibleResults[0].name == "Serum")

        // Simulate "Hidden" sidebar + "Serum" search (dashboard shows hidden)
        let hiddenResults = plugins
            .filter { $0.isHidden }
            .filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        #expect(hiddenResults.count == 1)
        #expect(hiddenResults[0].name == "Serum FX")
    }

    @Test("Newly reconciled plugins default to not hidden")
    func newPluginsNotHidden() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)

        let scanned = [
            makeMetadata(name: "NewPlugin", bundleID: "com.new.plugin", version: "1.0.0"),
        ]
        _ = try await reconciler.reconcile(scannedPlugins: scanned)

        let context = ModelContext(container)
        let plugins = try context.fetch(FetchDescriptor<Plugin>())
        #expect(plugins.count == 1)
        #expect(plugins.first?.isHidden == false)
    }
}
