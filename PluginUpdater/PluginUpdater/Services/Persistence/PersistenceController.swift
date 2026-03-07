import Foundation
import SwiftData

enum PersistenceController {
    static let modelSchema = Schema([
        Plugin.self,
        PluginVersion.self,
        VendorInfo.self,
        ScanLocation.self,
    ])

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let config: ModelConfiguration
        if inMemory {
            config = ModelConfiguration(
                schema: modelSchema,
                isStoredInMemoryOnly: true
            )
        } else {
            config = ModelConfiguration(
                schema: modelSchema,
                url: storeURL
            )
        }
        return try ModelContainer(for: modelSchema, configurations: [config])
    }

    static var storeURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent("com.tomioueda.PluginUpdater")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        return appDir.appendingPathComponent("PluginUpdater.store")
    }

    @MainActor
    static func seedDefaultScanLocations(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<ScanLocation>()
        let existing = try context.fetch(descriptor)
        guard existing.isEmpty else { return }

        for location in Constants.defaultScanLocations {
            let scanLocation = ScanLocation(
                path: location.path,
                format: location.format,
                isDefault: true,
                isEnabled: true
            )
            context.insert(scanLocation)
        }
        try context.save()
    }
}
