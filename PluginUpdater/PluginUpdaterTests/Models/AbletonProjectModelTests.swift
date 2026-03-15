import Testing
import Foundation
import SwiftData
@testable import PluginUpdater

@Suite("AbletonProject Model Tests")
struct AbletonProjectModelTests {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    @Test("Computes installed plugin count")
    func computesInstalledPluginCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = AbletonProject(
            filePath: "/test/project.als",
            name: "Test",
            lastModified: .now,
            fileSize: 1024
        )
        context.insert(project)
        project.plugins.append(AbletonProjectPlugin(pluginName: "A", pluginType: "au", isInstalled: true))
        project.plugins.append(AbletonProjectPlugin(pluginName: "B", pluginType: "vst3", isInstalled: true))
        project.plugins.append(AbletonProjectPlugin(pluginName: "C", pluginType: "vst2", isInstalled: false))
        try context.save()
        #expect(project.installedPluginCount == 2)
    }

    @Test("Computes missing plugin count")
    func computesMissingPluginCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = AbletonProject(
            filePath: "/test/project.als",
            name: "Test",
            lastModified: .now,
            fileSize: 1024
        )
        context.insert(project)
        project.plugins.append(AbletonProjectPlugin(pluginName: "A", pluginType: "au", isInstalled: true))
        project.plugins.append(AbletonProjectPlugin(pluginName: "B", pluginType: "vst3", isInstalled: true))
        project.plugins.append(AbletonProjectPlugin(pluginName: "C", pluginType: "vst2", isInstalled: false))
        try context.save()
        #expect(project.missingPluginCount == 1)
    }

    @Test("Cascade deletes plugins when project is deleted")
    func cascadeDeletesPlugins() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = AbletonProject(
            filePath: "/test/project.als",
            name: "Test",
            lastModified: .now,
            fileSize: 1024
        )
        context.insert(project)
        project.plugins.append(AbletonProjectPlugin(pluginName: "A", pluginType: "au"))
        project.plugins.append(AbletonProjectPlugin(pluginName: "B", pluginType: "vst3"))
        try context.save()

        context.delete(project)
        try context.save()

        let remainingPlugins = try context.fetch(FetchDescriptor<AbletonProjectPlugin>())
        #expect(remainingPlugins.isEmpty)
    }
}
