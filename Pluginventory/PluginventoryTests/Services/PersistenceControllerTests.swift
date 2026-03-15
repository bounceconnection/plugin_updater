import Testing
import Foundation
import SwiftData
@testable import Pluginventory

@Suite("PersistenceController Tests")
struct PersistenceControllerTests {

    @Test("Creates in-memory container successfully")
    func inMemoryContainer() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        #expect(!container.schema.entities.isEmpty)
    }

    @Test("In-memory container can insert and fetch Plugin")
    func insertAndFetch() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let plugin = Plugin(
            name: "TestPlugin",
            bundleIdentifier: "com.test.plugin",
            format: .vst3,
            currentVersion: "1.0",
            path: "/tmp/test.vst3"
        )
        context.insert(plugin)
        try context.save()

        let descriptor = FetchDescriptor<Plugin>()
        let results = try context.fetch(descriptor)
        #expect(results.count == 1)
        #expect(results[0].name == "TestPlugin")
    }

    @Test("Seed default scan locations inserts all defaults")
    @MainActor
    func seedDefaults() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext

        try PersistenceController.seedDefaultScanLocations(in: context)

        let descriptor = FetchDescriptor<ScanLocation>()
        let locations = try context.fetch(descriptor)
        #expect(locations.count == Constants.defaultScanLocations.count)

        // All should be marked as default and enabled
        for loc in locations {
            #expect(loc.isDefault == true)
            #expect(loc.isEnabled == true)
        }
    }

    @Test("Seed default scan locations is idempotent")
    @MainActor
    func seedIdempotent() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = container.mainContext

        try PersistenceController.seedDefaultScanLocations(in: context)
        try PersistenceController.seedDefaultScanLocations(in: context) // second call

        let descriptor = FetchDescriptor<ScanLocation>()
        let locations = try context.fetch(descriptor)
        #expect(locations.count == Constants.defaultScanLocations.count)
    }

    @Test("Schema includes all expected models")
    func schemaEntities() {
        let schema = PersistenceController.modelSchema
        let entityNames = schema.entities.map { $0.name }
        #expect(entityNames.contains("Plugin"))
        #expect(entityNames.contains("PluginVersion"))
        #expect(entityNames.contains("VendorInfo"))
        #expect(entityNames.contains("ScanLocation"))
    }
}
