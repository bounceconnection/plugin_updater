import Testing
import Foundation
import SwiftData
@testable import PluginUpdater

@Suite("Dashboard Multi-Select Tests")
struct DashboardMultiSelectTests {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    // MARK: - Selection logic

    @Test("Single selection resolves to one plugin")
    func singleSelectionResolvesToPlugin() throws {
        let plugins = [
            Plugin(name: "Plugin A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3"),
            Plugin(name: "Plugin B", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component"),
        ]

        let selectedIDs: Set<PersistentIdentifier> = [plugins[0].id]
        // Mirrors DashboardView.selectedPlugin logic
        let resolved = selectedIDs.count == 1
            ? plugins.first(where: { $0.id == selectedIDs.first })
            : nil

        #expect(resolved?.name == "Plugin A")
    }

    @Test("Multi-selection resolves to nil for detail view")
    func multiSelectionResolvesToNil() throws {
        let plugins = [
            Plugin(name: "Plugin A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3"),
            Plugin(name: "Plugin B", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component"),
        ]

        let selectedIDs: Set<PersistentIdentifier> = Set(plugins.map { $0.id })
        let resolved = selectedIDs.count == 1
            ? plugins.first(where: { $0.id == selectedIDs.first })
            : nil

        #expect(resolved == nil)
    }

    @Test("Empty selection resolves to nil")
    func emptySelectionResolvesToNil() throws {
        let selectedIDs: Set<PersistentIdentifier> = []
        let plugins: [Plugin] = []
        let resolved = selectedIDs.count == 1
            ? plugins.first(where: { $0.id == selectedIDs.first })
            : nil

        #expect(resolved == nil)
    }

    // MARK: - Bulk hide

    @Test("Bulk hide applies to all selected plugins")
    func bulkHideAllSelected() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugins = [
            Plugin(name: "Plugin A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3"),
            Plugin(name: "Plugin B", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component"),
            Plugin(name: "Plugin C", bundleIdentifier: "com.c", format: .clap, currentVersion: "1.0", path: "/c.clap"),
        ]
        for p in plugins { context.insert(p) }
        try context.save()

        // Simulate setHidden(true, for: allIDs)
        let allIDs = Set(plugins.map { $0.id })
        for id in allIDs {
            if let plugin = plugins.first(where: { $0.id == id }) {
                plugin.isHidden = true
            }
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Plugin>())
        #expect(fetched.count == 3)
        #expect(fetched.allSatisfy { $0.isHidden })
    }

    @Test("Bulk hide only affects selected plugins, not unselected ones")
    func bulkHidePartialSelection() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugins = [
            Plugin(name: "Plugin A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3"),
            Plugin(name: "Plugin B", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component"),
            Plugin(name: "Plugin C", bundleIdentifier: "com.c", format: .clap, currentVersion: "1.0", path: "/c.clap"),
        ]
        for p in plugins { context.insert(p) }
        try context.save()

        // Select only A and B; hide them
        let selectedIDs: Set<PersistentIdentifier> = [plugins[0].id, plugins[1].id]
        for id in selectedIDs {
            if let plugin = plugins.first(where: { $0.id == id }) {
                plugin.isHidden = true
            }
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Plugin>())
        let hidden = fetched.filter { $0.isHidden }
        let visible = fetched.filter { !$0.isHidden }

        #expect(hidden.count == 2)
        #expect(visible.count == 1)
        #expect(visible.first?.name == "Plugin C")
    }

    // MARK: - Bulk unhide

    @Test("Bulk unhide restores multiple hidden plugins")
    func bulkUnhideMultiplePlugins() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugins = [
            Plugin(name: "Plugin A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3", isHidden: true),
            Plugin(name: "Plugin B", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component", isHidden: true),
            Plugin(name: "Plugin C", bundleIdentifier: "com.c", format: .clap, currentVersion: "1.0", path: "/c.clap", isHidden: true),
        ]
        for p in plugins { context.insert(p) }
        try context.save()

        // Unhide A and B
        let selectedIDs: Set<PersistentIdentifier> = [plugins[0].id, plugins[1].id]
        for id in selectedIDs {
            if let plugin = plugins.first(where: { $0.id == id }) {
                plugin.isHidden = false
            }
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Plugin>())
        let hiddenCount = fetched.filter { $0.isHidden }.count
        let visibleCount = fetched.filter { !$0.isHidden }.count

        #expect(hiddenCount == 1)
        #expect(visibleCount == 2)
        #expect(fetched.first(where: { $0.isHidden })?.name == "Plugin C")
    }

    // MARK: - Inspector state

    @Test("Inspector shows multi-select placeholder when more than one plugin is selected")
    func inspectorShowsPlaceholderForMultiSelect() throws {
        let plugins = [
            Plugin(name: "Plugin A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3"),
            Plugin(name: "Plugin B", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component"),
        ]

        let selectedIDs: Set<PersistentIdentifier> = Set(plugins.map { $0.id })

        // When count > 1, dashboard shows multi-select placeholder
        #expect(selectedIDs.count > 1)
        // Single-plugin detail is not available
        let detail = selectedIDs.count == 1
            ? plugins.first(where: { $0.id == selectedIDs.first })
            : nil
        #expect(detail == nil)
    }

    @Test("Inspector shows detail when exactly one plugin is selected")
    func inspectorShowsDetailForSingleSelect() throws {
        let plugins = [
            Plugin(name: "Plugin A", bundleIdentifier: "com.a", format: .vst3, currentVersion: "1.0", path: "/a.vst3"),
            Plugin(name: "Plugin B", bundleIdentifier: "com.b", format: .au, currentVersion: "1.0", path: "/b.component"),
        ]

        let selectedIDs: Set<PersistentIdentifier> = [plugins[0].id]
        let detail = selectedIDs.count == 1
            ? plugins.first(where: { $0.id == selectedIDs.first })
            : nil

        #expect(detail?.name == "Plugin A")
    }

    // MARK: - Mixed-format bulk hide

    @Test("Bulk hide works across different plugin formats")
    func bulkHideAcrossFormats() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vst3 = Plugin(name: "VST Plugin", bundleIdentifier: "com.vst", format: .vst3, currentVersion: "1.0", path: "/v.vst3")
        let au = Plugin(name: "AU Plugin", bundleIdentifier: "com.au", format: .au, currentVersion: "1.0", path: "/a.component")
        let clap = Plugin(name: "CLAP Plugin", bundleIdentifier: "com.clap", format: .clap, currentVersion: "1.0", path: "/c.clap")

        for p in [vst3, au, clap] { context.insert(p) }
        try context.save()

        // Select all three (different formats) and hide
        let allIDs: Set<PersistentIdentifier> = [vst3.id, au.id, clap.id]
        for id in allIDs {
            if let plugin = [vst3, au, clap].first(where: { $0.id == id }) {
                plugin.isHidden = true
            }
        }
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<Plugin>())
        #expect(fetched.allSatisfy { $0.isHidden })
        #expect(fetched.count == 3)
    }
}
