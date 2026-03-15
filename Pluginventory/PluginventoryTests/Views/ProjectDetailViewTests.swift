import Testing
import Foundation
import SwiftData
@testable import Pluginventory

@Suite("ProjectDetailView Plugin Filtering Tests")
struct ProjectDetailViewTests {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    private func makeProject(
        in context: ModelContext,
        plugins: [(name: String, type: String, installed: Bool)]
    ) throws -> AbletonProject {
        let project = AbletonProject(
            filePath: "/test/project.als",
            name: "Test Project",
            lastModified: .now,
            fileSize: 1024
        )
        context.insert(project)
        for p in plugins {
            project.plugins.append(AbletonProjectPlugin(
                pluginName: p.name,
                pluginType: p.type,
                isInstalled: p.installed
            ))
        }
        try context.save()
        return project
    }

    @Test("AU plugins are filtered and sorted alphabetically")
    func auPluginsSortedAlphabetically() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context, plugins: [
            (name: "Zebra2", type: "au", installed: true),
            (name: "Pro-L 2", type: "au", installed: true),
            (name: "Serum", type: "vst3", installed: true),
            (name: "Arpeggiator", type: "au", installed: false),
        ])

        let auPlugins = project.plugins
            .filter { $0.pluginType == "au" }
            .sorted { $0.pluginName.localizedCompare($1.pluginName) == .orderedAscending }

        #expect(auPlugins.count == 3)
        #expect(auPlugins[0].pluginName == "Arpeggiator")
        #expect(auPlugins[1].pluginName == "Pro-L 2")
        #expect(auPlugins[2].pluginName == "Zebra2")
    }

    @Test("VST3 plugins are filtered and sorted alphabetically")
    func vst3PluginsSortedAlphabetically() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context, plugins: [
            (name: "Vital", type: "vst3", installed: true),
            (name: "Pro-L 2", type: "au", installed: true),
            (name: "Diva", type: "vst3", installed: false),
            (name: "Serum", type: "vst3", installed: true),
        ])

        let vst3Plugins = project.plugins
            .filter { $0.pluginType == "vst3" }
            .sorted { $0.pluginName.localizedCompare($1.pluginName) == .orderedAscending }

        #expect(vst3Plugins.count == 3)
        #expect(vst3Plugins[0].pluginName == "Diva")
        #expect(vst3Plugins[1].pluginName == "Serum")
        #expect(vst3Plugins[2].pluginName == "Vital")
    }

    @Test("Empty project shows no plugins in any category")
    func emptyProjectShowsNoPlugins() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context, plugins: [])

        let auPlugins = project.plugins.filter { $0.pluginType == "au" }
        let vst3Plugins = project.plugins.filter { $0.pluginType == "vst3" }
        let vst2Plugins = project.plugins.filter { $0.pluginType == "vst2" }

        #expect(auPlugins.isEmpty)
        #expect(vst3Plugins.isEmpty)
        #expect(vst2Plugins.isEmpty)
        #expect(project.plugins.isEmpty)
    }

    @Test("VST2 plugins are filtered separately from VST3")
    func vst2PluginsFilteredSeparately() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try makeProject(in: context, plugins: [
            (name: "Sylenth1", type: "vst2", installed: true),
            (name: "Serum", type: "vst3", installed: true),
            (name: "Kontakt", type: "vst2", installed: false),
        ])

        let vst2Plugins = project.plugins
            .filter { $0.pluginType == "vst2" }
            .sorted { $0.pluginName.localizedCompare($1.pluginName) == .orderedAscending }

        #expect(vst2Plugins.count == 2)
        #expect(vst2Plugins[0].pluginName == "Kontakt")
        #expect(vst2Plugins[1].pluginName == "Sylenth1")
    }
}
