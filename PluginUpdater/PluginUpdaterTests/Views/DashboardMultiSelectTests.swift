import Testing
import Foundation
import SwiftData
@testable import PluginUpdater

/// Tests for the multi-select behavior added to DashboardView (issue #11).
/// These tests cover the model-layer logic that powers multi-select:
/// bulk hide/unhide by a set of PersistentIdentifiers, and the PluginRow
/// identity used by the Table selection binding.
@Suite("Dashboard Multi-Select Tests")
struct DashboardMultiSelectTests {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    // MARK: - PluginRow identity

    @Test("PluginRow id matches Plugin id for Table selection")
    func pluginRowIDMatchesPluginID() throws {
        let plugin = Plugin(
            name: "Serum",
            bundleIdentifier: "com.xferrecords.Serum",
            format: .vst3,
            currentVersion: "1.35",
            path: "/Library/Audio/Plug-Ins/VST3/Serum.vst3"
        )
        let container = try makeContainer()
        let context = ModelContext(container)
        context.insert(plugin)
        try context.save()

        let row = PluginRow(plugin: plugin, availableVersion: "1.36", hasUpdate: true, downloadURL: nil)
        #expect(row.id == plugin.id)
    }

    @Test("PluginRow exposes correct computed properties")
    func pluginRowComputedProperties() {
        let plugin = Plugin(
            name: "Pro-Q 3",
            bundleIdentifier: "com.fabfilter.ProQ3",
            format: .vst3,
            currentVersion: "3.21",
            path: "/Library/Audio/Plug-Ins/VST3/FabFilter Pro-Q 3.vst3",
            vendorName: "FabFilter"
        )
        let row = PluginRow(plugin: plugin, availableVersion: "3.22", hasUpdate: true, downloadURL: "https://example.com")
        #expect(row.name == "Pro-Q 3")
        #expect(row.vendorName == "FabFilter")
        #expect(row.formatRawValue == "vst3")
        #expect(row.currentVersion == "3.21")
        #expect(row.updatePriority == 2)
        #expect(row.hasDownload == 1)
    }

    @Test("PluginRow updatePriority: no data = 0, up to date = 1, update available = 2")
    func pluginRowUpdatePriority() {
        let plugin = Plugin(name: "X", bundleIdentifier: "com.x", format: .vst3, currentVersion: "1.0", path: "/x.vst3")
        let noData = PluginRow(plugin: plugin, availableVersion: "—", hasUpdate: false, downloadURL: nil)
        let upToDate = PluginRow(plugin: plugin, availableVersion: "1.0", hasUpdate: false, downloadURL: nil)
        let hasUpdate = PluginRow(plugin: plugin, availableVersion: "2.0", hasUpdate: true, downloadURL: nil)

        #expect(noData.updatePriority == 0)
        #expect(upToDate.updatePriority == 1)
        #expect(hasUpdate.updatePriority == 2)
    }

    // MARK: - Bulk hide via Set<PersistentIdentifier>

    @Test("Bulk hide: hiding two plugins sets both isHidden = true")
    func bulkHideTwoPlugins() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pluginA = Plugin(name: "Plugin A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3")
        let pluginB = Plugin(name: "Plugin B", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component")
        let pluginC = Plugin(name: "Plugin C", bundleIdentifier: "com.c", format: .clap, currentVersion: "1.0", path: "/c.clap")

        context.insert(pluginA)
        context.insert(pluginB)
        context.insert(pluginC)
        try context.save()

        // Simulate DashboardView.setHidden(_:for:) with 2 IDs
        let ids: Set<PersistentIdentifier> = [pluginA.id, pluginB.id]
        let allPlugins = [pluginA, pluginB, pluginC]
        for id in ids {
            if let p = allPlugins.first(where: { $0.id == id }) {
                p.isHidden = true
            }
        }
        try context.save()

        let descriptor = FetchDescriptor<Plugin>()
        let fetched = try context.fetch(descriptor)
        let hiddenNames = fetched.filter { $0.isHidden }.map { $0.name }.sorted()
        #expect(hiddenNames == ["Plugin A", "Plugin B"])

        let visibleNames = fetched.filter { !$0.isHidden }.map { $0.name }
        #expect(visibleNames == ["Plugin C"])
    }

    @Test("Bulk unhide: unhiding multiple hidden plugins sets all isHidden = false")
    func bulkUnhideMultiplePlugins() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pluginA = Plugin(name: "Plugin A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3", isHidden: true)
        let pluginB = Plugin(name: "Plugin B", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component", isHidden: true)

        context.insert(pluginA)
        context.insert(pluginB)
        try context.save()

        // Simulate setHidden(false, for: [pluginA.id, pluginB.id])
        let ids: Set<PersistentIdentifier> = [pluginA.id, pluginB.id]
        let allPlugins = [pluginA, pluginB]
        for id in ids {
            if let p = allPlugins.first(where: { $0.id == id }) {
                p.isHidden = false
            }
        }
        try context.save()

        let descriptor = FetchDescriptor<Plugin>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.allSatisfy { !$0.isHidden })
    }

    @Test("Bulk hide with empty set changes nothing")
    func bulkHideEmptySet() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugin = Plugin(name: "Plugin A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3")
        context.insert(plugin)
        try context.save()

        // Simulate setHidden(true, for: []) — empty selection
        let ids: Set<PersistentIdentifier> = []
        for id in ids {
            if let p = [plugin].first(where: { $0.id == id }) {
                p.isHidden = true
            }
        }
        try context.save()

        let descriptor = FetchDescriptor<Plugin>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched[0].isHidden == false)
    }

    // MARK: - Selection → inspector state logic

    @Test("Single selection returns the matching plugin")
    func singleSelectionReturnsPlugin() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugin = Plugin(name: "Serum", bundleIdentifier: "com.xfer.serum", format: .vst3, currentVersion: "1.35", path: "/serum.vst3")
        context.insert(plugin)
        try context.save()

        let allPlugins = [plugin]
        // Simulate: selectedPluginIDs.count == 1
        let selectedIDs: Set<PersistentIdentifier> = [plugin.id]
        let selectedPlugin: Plugin? = selectedIDs.count == 1
            ? allPlugins.first { $0.id == selectedIDs.first! }
            : nil

        #expect(selectedPlugin?.name == "Serum")
    }

    @Test("Multi-selection (2+) returns nil for selectedPlugin")
    func multiSelectionReturnsNil() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let pluginA = Plugin(name: "Serum", bundleIdentifier: "com.xfer.serum", format: .vst3, currentVersion: "1.35", path: "/serum.vst3")
        let pluginB = Plugin(name: "Kontakt", bundleIdentifier: "com.ni.kontakt", format: .au, currentVersion: "7.0", path: "/kontakt.component")
        context.insert(pluginA)
        context.insert(pluginB)
        try context.save()

        let allPlugins = [pluginA, pluginB]
        // Simulate: selectedPluginIDs.count > 1 → selectedPlugin = nil
        let selectedIDs: Set<PersistentIdentifier> = [pluginA.id, pluginB.id]
        let selectedPlugin: Plugin? = selectedIDs.count == 1
            ? allPlugins.first { $0.id == selectedIDs.first! }
            : nil

        #expect(selectedPlugin == nil)
    }

    @Test("Empty selection returns nil for selectedPlugin")
    func emptySelectionReturnsNil() {
        let allPlugins: [Plugin] = []
        let selectedIDs: Set<PersistentIdentifier> = []
        let selectedPlugin: Plugin? = selectedIDs.count == 1
            ? allPlugins.first { $0.id == selectedIDs.first! }
            : nil

        #expect(selectedPlugin == nil)
    }

    // MARK: - Context menu label logic

    @Test("Context menu label is singular for 1 selection")
    func contextMenuLabelSingular() {
        let ids: Set<PersistentIdentifier> = makeOneElementSet()
        let label = ids.count == 1 ? "Plugin" : "\(ids.count) Plugins"
        #expect(label == "Plugin")
    }

    @Test("Context menu label is plural for multiple selections")
    func contextMenuLabelPlural() {
        let ids: Set<PersistentIdentifier> = makeTwoElementSet()
        let label = ids.count == 1 ? "Plugin" : "\(ids.count) Plugins"
        #expect(label == "2 Plugins")
    }

    // MARK: - Helpers

    /// Returns a Set with one synthetic PersistentIdentifier-like value using real Plugin objects.
    private func makeOneElementSet() -> Set<PersistentIdentifier> {
        guard let container = try? PersistenceController.makeContainer(inMemory: true) else { return [] }
        let context = ModelContext(container)
        let plugin = Plugin(name: "A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3")
        context.insert(plugin)
        try? context.save()
        return [plugin.id]
    }

    private func makeTwoElementSet() -> Set<PersistentIdentifier> {
        guard let container = try? PersistenceController.makeContainer(inMemory: true) else { return [] }
        let context = ModelContext(container)
        let p1 = Plugin(name: "A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3")
        let p2 = Plugin(name: "B", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component")
        context.insert(p1)
        context.insert(p2)
        try? context.save()
        return [p1.id, p2.id]
    }
}
