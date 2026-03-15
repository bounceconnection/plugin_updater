import Testing
import Foundation
import SwiftData
@testable import Pluginventory

@Suite("Plugin Model Tests")
struct PluginModelTests {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    @Test("Create plugin with all fields")
    func createPlugin() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugin = Plugin(
            name: "Serum",
            bundleIdentifier: "com.xferrecords.Serum",
            format: .vst3,
            currentVersion: "1.35",
            path: "/Library/Audio/Plug-Ins/VST3/Serum.vst3",
            vendorName: "Xfer Records"
        )
        context.insert(plugin)
        try context.save()

        let descriptor = FetchDescriptor<Plugin>()
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched[0].name == "Serum")
        #expect(fetched[0].bundleIdentifier == "com.xferrecords.Serum")
        #expect(fetched[0].format == .vst3)
        #expect(fetched[0].currentVersion == "1.35")
        #expect(fetched[0].vendorName == "Xfer Records")
        #expect(fetched[0].isRemoved == false)
        #expect(fetched[0].versionHistory.isEmpty)
    }

    @Test("Plugin defaults vendor to Unknown")
    func pluginDefaultVendor() throws {
        let plugin = Plugin(
            name: "TestPlugin",
            bundleIdentifier: "com.test.plugin",
            format: .au,
            currentVersion: "1.0",
            path: "/Library/Audio/Plug-Ins/Components/Test.component"
        )
        #expect(plugin.vendorName == "Unknown")
    }

    @Test("Plugin pathURL returns correct URL")
    func pluginPathURL() {
        let plugin = Plugin(
            name: "Test",
            bundleIdentifier: "com.test",
            format: .clap,
            currentVersion: "1.0",
            path: "/Library/Audio/Plug-Ins/CLAP/Test.clap"
        )
        #expect(plugin.pathURL.path == "/Library/Audio/Plug-Ins/CLAP/Test.clap")
    }

    @Test("Plugin version history cascade delete")
    func versionHistoryCascadeDelete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugin = Plugin(
            name: "Pro-Q 3",
            bundleIdentifier: "com.fabfilter.ProQ3",
            format: .vst3,
            currentVersion: "3.21",
            path: "/Library/Audio/Plug-Ins/VST3/FabFilter Pro-Q 3.vst3"
        )
        context.insert(plugin)

        let v1 = PluginVersion(version: "3.20", previousVersion: "3.19")
        v1.plugin = plugin
        plugin.versionHistory.append(v1)

        let v2 = PluginVersion(version: "3.21", previousVersion: "3.20")
        v2.plugin = plugin
        plugin.versionHistory.append(v2)

        try context.save()

        // Verify versions exist
        let versionDescriptor = FetchDescriptor<PluginVersion>()
        let versions = try context.fetch(versionDescriptor)
        #expect(versions.count == 2)

        // Delete plugin - versions should cascade
        context.delete(plugin)
        try context.save()

        let remainingVersions = try context.fetch(versionDescriptor)
        #expect(remainingVersions.isEmpty)
    }

    @Test("Plugin soft delete preserves record")
    func softDelete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let plugin = Plugin(
            name: "Kontakt",
            bundleIdentifier: "com.native-instruments.Kontakt7",
            format: .au,
            currentVersion: "7.5",
            path: "/Library/Audio/Plug-Ins/Components/Kontakt 7.component"
        )
        context.insert(plugin)
        try context.save()

        // Soft-delete
        plugin.isRemoved = true
        try context.save()

        let descriptor = FetchDescriptor<Plugin>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched[0].isRemoved == true)
    }

    @Test("Plugin-VendorInfo relationship")
    func pluginVendorRelationship() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let vendor = VendorInfo(name: "FabFilter", websiteURL: "https://www.fabfilter.com")
        context.insert(vendor)

        let plugin = Plugin(
            name: "Pro-Q 3",
            bundleIdentifier: "com.fabfilter.ProQ3",
            format: .vst3,
            currentVersion: "3.21",
            path: "/Library/Audio/Plug-Ins/VST3/FabFilter Pro-Q 3.vst3",
            vendorName: "FabFilter"
        )
        context.insert(plugin)
        plugin.vendor = vendor

        try context.save()

        let vendorDescriptor = FetchDescriptor<VendorInfo>()
        let fetchedVendors = try context.fetch(vendorDescriptor)
        #expect(fetchedVendors.count == 1)
        #expect(fetchedVendors[0].plugins.count == 1)
        #expect(fetchedVendors[0].plugins[0].name == "Pro-Q 3")
    }
}
