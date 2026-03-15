import Testing
import Foundation
import SwiftData
@testable import Pluginventory

@Suite("ProjectReconciler Tests")
struct ProjectReconcilerTests {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    private func makeParsedProject(
        name: String,
        filePath: String,
        plugins: [AbletonProjectParser.ParsedPlugin] = []
    ) -> AbletonProjectParser.ParsedProject {
        AbletonProjectParser.ParsedProject(
            name: name,
            filePath: filePath,
            lastModified: .now,
            fileSize: 1024,
            abletonVersion: "Ableton Live 12.1.5",
            plugins: plugins
        )
    }

    private func makeParsedPlugin(
        name: String,
        type: String,
        vendor: String? = nil
    ) -> AbletonProjectParser.ParsedPlugin {
        AbletonProjectParser.ParsedPlugin(
            pluginName: name,
            pluginType: type,
            auComponentType: nil,
            auComponentSubType: nil,
            auComponentManufacturer: nil,
            vst3TUID: nil,
            vendorName: vendor
        )
    }

    @Test("Inserts new projects")
    func insertsNewProjects() async throws {
        let container = try makeContainer()
        let reconciler = ProjectReconciler(modelContainer: container)
        let parsed = [
            makeParsedProject(name: "Track A", filePath: "/projects/track-a.als", plugins: [
                makeParsedPlugin(name: "Serum", type: "vst3"),
                makeParsedPlugin(name: "Pro-L 2", type: "au"),
            ]),
            makeParsedProject(name: "Track B", filePath: "/projects/track-b.als", plugins: [
                makeParsedPlugin(name: "Sylenth1", type: "vst2"),
            ]),
        ]
        let result = try await reconciler.reconcile(parsedProjects: parsed)
        #expect(result.newProjects == 2)
        #expect(result.updatedProjects == 0)

        let context = ModelContext(container)
        let projects = try context.fetch(FetchDescriptor<AbletonProject>())
        #expect(projects.count == 2)
        let trackA = projects.first { $0.name == "Track A" }
        #expect(trackA?.plugins.count == 2)
    }

    @Test("Updates existing project plugins")
    func updatesExistingProject() async throws {
        let container = try makeContainer()

        // Insert initial project with an older lastModified date
        let context = ModelContext(container)
        let oldDate = Date.now.addingTimeInterval(-3600)
        let project = AbletonProject(
            filePath: "/projects/track-a.als",
            name: "Track A",
            lastModified: oldDate,
            fileSize: 1024
        )
        let oldPlugin = AbletonProjectPlugin(pluginName: "OldPlugin", pluginType: "vst3")
        project.plugins.append(oldPlugin)
        context.insert(project)
        try context.save()

        // Re-scan with different plugins and a newer lastModified
        let reconciler = ProjectReconciler(modelContainer: container)
        let parsed = [
            makeParsedProject(name: "Track A", filePath: "/projects/track-a.als", plugins: [
                makeParsedPlugin(name: "NewPlugin", type: "au"),
            ]),
        ]
        let result = try await reconciler.reconcile(parsedProjects: parsed)
        #expect(result.updatedProjects == 1)
        #expect(result.newProjects == 0)

        let freshContext = ModelContext(container)
        let projects = try freshContext.fetch(FetchDescriptor<AbletonProject>())
        #expect(projects.count == 1)
        #expect(projects[0].plugins.count == 1)
        #expect(projects[0].plugins[0].pluginName == "NewPlugin")
    }

    @Test("Marks removed projects on full scan")
    func marksRemovedProjectsOnFullScan() async throws {
        let container = try makeContainer()

        let context = ModelContext(container)
        let project = AbletonProject(
            filePath: "/projects/gone.als",
            name: "Gone",
            lastModified: .now,
            fileSize: 512
        )
        context.insert(project)
        try context.save()

        let reconciler = ProjectReconciler(modelContainer: container)
        let result = try await reconciler.reconcile(parsedProjects: [], fullScan: true)
        #expect(result.removedProjects == 1)

        let freshContext = ModelContext(container)
        let projects = try freshContext.fetch(FetchDescriptor<AbletonProject>())
        #expect(projects[0].isRemoved == true)
    }

    @Test("Preserves projects on incremental scan")
    func preservesProjectsOnIncrementalScan() async throws {
        let container = try makeContainer()

        let context = ModelContext(container)
        let project = AbletonProject(
            filePath: "/projects/kept.als",
            name: "Kept",
            lastModified: .now,
            fileSize: 512
        )
        context.insert(project)
        try context.save()

        let reconciler = ProjectReconciler(modelContainer: container)
        let result = try await reconciler.reconcile(parsedProjects: [], fullScan: false)
        #expect(result.removedProjects == 0)

        let freshContext = ModelContext(container)
        let projects = try freshContext.fetch(FetchDescriptor<AbletonProject>())
        #expect(projects[0].isRemoved == false)
    }

    @Test("Matches plugins against installed database")
    func matchesPluginsAgainstInstalledDatabase() async throws {
        let container = try makeContainer()

        // Pre-insert an installed plugin
        let context = ModelContext(container)
        let installed = Plugin(
            name: "Pro-L 2",
            bundleIdentifier: "com.fabfilter.ProL2",
            format: .au,
            currentVersion: "2.1.0",
            path: "/Library/Audio/Plug-Ins/Components/Pro-L 2.component",
            vendorName: "FabFilter"
        )
        context.insert(installed)
        try context.save()

        let reconciler = ProjectReconciler(modelContainer: container)
        let parsed = [
            makeParsedProject(name: "TestProject", filePath: "/projects/test.als", plugins: [
                makeParsedPlugin(name: "Pro-L 2", type: "au", vendor: "FabFilter"),
            ]),
        ]
        _ = try await reconciler.reconcile(parsedProjects: parsed)

        let freshContext = ModelContext(container)
        let projects = try freshContext.fetch(FetchDescriptor<AbletonProject>())
        let projectPlugin = projects[0].plugins[0]
        #expect(projectPlugin.isInstalled == true)
        #expect(projectPlugin.matchedPluginID != nil)
    }

    @Test("Sets not installed for missing plugins")
    func setsNotInstalledForMissingPlugins() async throws {
        let container = try makeContainer()
        let reconciler = ProjectReconciler(modelContainer: container)
        let parsed = [
            makeParsedProject(name: "TestProject", filePath: "/projects/test.als", plugins: [
                makeParsedPlugin(name: "NonExistent", type: "vst3"),
            ]),
        ]
        _ = try await reconciler.reconcile(parsedProjects: parsed)

        let context = ModelContext(container)
        let projects = try context.fetch(FetchDescriptor<AbletonProject>())
        #expect(projects[0].plugins[0].isInstalled == false)
    }

    @Test("refreshPluginMatching updates flags after new plugin install")
    func refreshPluginMatchingUpdatesFlags() async throws {
        let container = try makeContainer()
        let reconciler = ProjectReconciler(modelContainer: container)

        // First: reconcile a project with a plugin that isn't installed
        let parsed = [
            makeParsedProject(name: "TestProject", filePath: "/projects/test.als", plugins: [
                makeParsedPlugin(name: "NewSynth", type: "vst3"),
            ]),
        ]
        _ = try await reconciler.reconcile(parsedProjects: parsed)

        // Verify it's not installed
        let context1 = ModelContext(container)
        var projects = try context1.fetch(FetchDescriptor<AbletonProject>())
        #expect(projects[0].plugins[0].isInstalled == false)

        // Now "install" the plugin
        let context2 = ModelContext(container)
        let installed = Plugin(
            name: "NewSynth",
            bundleIdentifier: "com.test.newsynth",
            format: .vst3,
            currentVersion: "1.0.0",
            path: "/Library/Audio/Plug-Ins/VST3/NewSynth.vst3"
        )
        context2.insert(installed)
        try context2.save()

        // Refresh matching
        try await reconciler.refreshPluginMatching()

        // Now it should be installed
        let context3 = ModelContext(container)
        projects = try context3.fetch(FetchDescriptor<AbletonProject>())
        #expect(projects[0].plugins[0].isInstalled == true)
    }

    // MARK: - markMissingProjects Tests

    @Test("markMissingProjects marks unseen as removed")
    func markMissingProjectsMarksUnseenAsRemoved() async throws {
        let container = try makeContainer()

        let context = ModelContext(container)
        for (name, path) in [
            ("A", "/projects/a.als"),
            ("B", "/projects/b.als"),
            ("C", "/projects/c.als"),
        ] {
            let project = AbletonProject(
                filePath: path, name: name, lastModified: .now, fileSize: 512
            )
            context.insert(project)
        }
        try context.save()

        let reconciler = ProjectReconciler(modelContainer: container)
        let scannedPaths: Set<String> = ["/projects/a.als", "/projects/b.als"]
        let removedCount = try await reconciler.markMissingProjects(scannedPaths: scannedPaths)
        #expect(removedCount == 1)

        let freshContext = ModelContext(container)
        let projects = try freshContext.fetch(FetchDescriptor<AbletonProject>())
        let removed = projects.filter { $0.isRemoved }
        #expect(removed.count == 1)
        #expect(removed[0].name == "C")
    }

    @Test("markMissingProjects preserves already-removed projects")
    func markMissingProjectsPreservesAlreadyRemoved() async throws {
        let container = try makeContainer()

        let context = ModelContext(container)
        let project = AbletonProject(
            filePath: "/projects/old.als", name: "Old", lastModified: .now, fileSize: 512
        )
        project.isRemoved = true
        context.insert(project)
        try context.save()

        let reconciler = ProjectReconciler(modelContainer: container)
        let removedCount = try await reconciler.markMissingProjects(scannedPaths: [])
        // Should be 0 because the project was already removed
        #expect(removedCount == 0)
    }

    @Test("markMissingProjects with all paths scanned removes nothing")
    func markMissingProjectsAllScanned() async throws {
        let container = try makeContainer()

        let context = ModelContext(container)
        for (name, path) in [("A", "/projects/a.als"), ("B", "/projects/b.als")] {
            let project = AbletonProject(
                filePath: path, name: name, lastModified: .now, fileSize: 512
            )
            context.insert(project)
        }
        try context.save()

        let reconciler = ProjectReconciler(modelContainer: container)
        let removedCount = try await reconciler.markMissingProjects(
            scannedPaths: ["/projects/a.als", "/projects/b.als"]
        )
        #expect(removedCount == 0)
    }

    @Test("Batch reconcile with fullScan false does not remove existing projects")
    func batchReconcileNoRemoval() async throws {
        let container = try makeContainer()

        // Pre-insert a project
        let context = ModelContext(container)
        let existing = AbletonProject(
            filePath: "/projects/existing.als", name: "Existing", lastModified: .now, fileSize: 512
        )
        context.insert(existing)
        try context.save()

        // Reconcile a different project with fullScan=false
        let reconciler = ProjectReconciler(modelContainer: container)
        let parsed = [
            makeParsedProject(name: "New", filePath: "/projects/new.als"),
        ]
        let result = try await reconciler.reconcile(parsedProjects: parsed, fullScan: false)
        #expect(result.newProjects == 1)
        #expect(result.removedProjects == 0)

        // Existing project should still be there and not removed
        let freshContext = ModelContext(container)
        let projects = try freshContext.fetch(FetchDescriptor<AbletonProject>())
        #expect(projects.count == 2)
        let existingProject = projects.first { $0.name == "Existing" }
        #expect(existingProject?.isRemoved == false)
    }
}
