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
}
