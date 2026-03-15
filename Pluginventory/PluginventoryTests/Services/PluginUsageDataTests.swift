import Testing
import Foundation
import SwiftData
@testable import Pluginventory

@Suite("Plugin Usage Data Tests")
struct PluginUsageDataTests {

    // MARK: - Parser instance count tests

    private func makeALSFixture(xml: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ALSTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let alsURL = tempDir.appendingPathComponent("test.als")
        let inputURL = tempDir.appendingPathComponent("test.xml")
        try xml.data(using: .utf8)!.write(to: inputURL)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/gzip")
        proc.arguments = ["-c", inputURL.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        try proc.run()
        let gzData = pipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        try gzData.write(to: alsURL)
        return alsURL
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    @Test("Duplicate AU plugins accumulate instanceCount")
    func duplicateAUPluginsAccumulateInstanceCount() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet>
            <Tracks>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <AuPluginInfo>
                      <Name Value="Pro-L 2"/>
                      <Manufacturer Value="FabFilter"/>
                      <ComponentType Value="1635085685"/>
                      <ComponentSubType Value="1349480050"/>
                      <ComponentManufacturer Value="1178683442"/>
                    </AuPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <AuPluginInfo>
                      <Name Value="Pro-L 2"/>
                      <Manufacturer Value="FabFilter"/>
                      <ComponentType Value="1635085685"/>
                      <ComponentSubType Value="1349480050"/>
                      <ComponentManufacturer Value="1178683442"/>
                    </AuPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <AuPluginInfo>
                      <Name Value="Pro-L 2"/>
                      <Manufacturer Value="FabFilter"/>
                      <ComponentType Value="1635085685"/>
                      <ComponentSubType Value="1349480050"/>
                      <ComponentManufacturer Value="1178683442"/>
                    </AuPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
            </Tracks>
          </LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.count == 1)
        #expect(project.plugins[0].instanceCount == 3)
    }

    @Test("Single plugin instance has instanceCount of 1")
    func singlePluginInstanceHasCountOfOne() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet>
            <Tracks>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <VstPluginInfo>
                      <PlugName Value="Sylenth1"/>
                    </VstPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
            </Tracks>
          </LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.count == 1)
        #expect(project.plugins[0].instanceCount == 1)
    }

    @Test("Different plugins each get their own instanceCount")
    func differentPluginsGetSeparateCounts() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet>
            <Tracks>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <VstPluginInfo><PlugName Value="PlugA"/></VstPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <VstPluginInfo><PlugName Value="PlugA"/></VstPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
              <AudioTrack>
                <DeviceChain>
                  <PluginDevice>
                    <VstPluginInfo><PlugName Value="PlugB"/></VstPluginInfo>
                  </PluginDevice>
                </DeviceChain>
              </AudioTrack>
            </Tracks>
          </LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.count == 2)
        let plugA = project.plugins.first { $0.pluginName == "PlugA" }
        let plugB = project.plugins.first { $0.pluginName == "PlugB" }
        #expect(plugA?.instanceCount == 2)
        #expect(plugB?.instanceCount == 1)
    }

    @Test("Empty project has no plugins and no instance counts")
    func emptyProjectHasNoUsageData() async throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <Ableton Creator="Ableton Live 12.1.5">
          <LiveSet><Tracks/></LiveSet>
        </Ableton>
        """
        let url = try makeALSFixture(xml: xml)
        defer { cleanup(url) }
        let parser = AbletonProjectParser()
        let project = try await parser.parse(fileURL: url)
        #expect(project.plugins.isEmpty)
    }

    // MARK: - Model instanceCount tests

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    @Test("AbletonProjectPlugin instanceCount defaults to 1")
    func instanceCountDefaultsToOne() throws {
        let plugin = AbletonProjectPlugin(pluginName: "TestPlugin", pluginType: "vst3")
        #expect(plugin.instanceCount == 1)
    }

    @Test("AbletonProjectPlugin instanceCount persists in SwiftData")
    func instanceCountPersistsInSwiftData() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = AbletonProject(
            filePath: "/test/project.als",
            name: "Test",
            lastModified: .now,
            fileSize: 1024
        )
        context.insert(project)
        let pp = AbletonProjectPlugin(
            pluginName: "Serum",
            pluginType: "vst3",
            isInstalled: true,
            instanceCount: 5
        )
        project.plugins.append(pp)
        try context.save()

        let freshContext = ModelContext(container)
        let projects = try freshContext.fetch(FetchDescriptor<AbletonProject>())
        #expect(projects[0].plugins[0].instanceCount == 5)
    }

    // MARK: - Reconciler instanceCount passthrough tests

    private func makeParsedPlugin(
        name: String,
        type: String,
        vendor: String? = nil,
        instanceCount: Int = 1
    ) -> AbletonProjectParser.ParsedPlugin {
        var p = AbletonProjectParser.ParsedPlugin(
            pluginName: name,
            pluginType: type,
            auComponentType: nil,
            auComponentSubType: nil,
            auComponentManufacturer: nil,
            vst3TUID: nil,
            vendorName: vendor
        )
        p.instanceCount = instanceCount
        return p
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

    @Test("Reconciler passes instanceCount through to AbletonProjectPlugin")
    func reconcilerPassesInstanceCountThrough() async throws {
        let container = try makeContainer()
        let reconciler = ProjectReconciler(modelContainer: container)
        let parsed = [
            makeParsedProject(name: "Track A", filePath: "/projects/track-a.als", plugins: [
                makeParsedPlugin(name: "Serum", type: "vst3", instanceCount: 4),
                makeParsedPlugin(name: "ProQ", type: "au", instanceCount: 7),
            ]),
        ]
        _ = try await reconciler.reconcile(parsedProjects: parsed)

        let context = ModelContext(container)
        let projects = try context.fetch(FetchDescriptor<AbletonProject>())
        let plugins = projects[0].plugins.sorted { $0.pluginName < $1.pluginName }
        #expect(plugins.count == 2)
        #expect(plugins[0].pluginName == "ProQ")
        #expect(plugins[0].instanceCount == 7)
        #expect(plugins[1].pluginName == "Serum")
        #expect(plugins[1].instanceCount == 4)
    }

    @Test("Reconciler defaults instanceCount to 1 when not specified")
    func reconcilerDefaultsInstanceCountToOne() async throws {
        let container = try makeContainer()
        let reconciler = ProjectReconciler(modelContainer: container)
        let parsed = [
            makeParsedProject(name: "Track B", filePath: "/projects/track-b.als", plugins: [
                makeParsedPlugin(name: "BasicPlug", type: "vst2"),
            ]),
        ]
        _ = try await reconciler.reconcile(parsedProjects: parsed)

        let context = ModelContext(container)
        let projects = try context.fetch(FetchDescriptor<AbletonProject>())
        #expect(projects[0].plugins[0].instanceCount == 1)
    }

    @Test("Reconciler preserves instanceCount when updating existing project")
    func reconcilerPreservesInstanceCountOnUpdate() async throws {
        let container = try makeContainer()

        // Insert initial project with an older lastModified
        let context = ModelContext(container)
        let project = AbletonProject(
            filePath: "/projects/track.als",
            name: "Track",
            lastModified: Date.now.addingTimeInterval(-3600),
            fileSize: 1024
        )
        let oldPlugin = AbletonProjectPlugin(
            pluginName: "Serum",
            pluginType: "vst3",
            instanceCount: 2
        )
        project.plugins.append(oldPlugin)
        context.insert(project)
        try context.save()

        // Re-scan with higher instance count
        let reconciler = ProjectReconciler(modelContainer: container)
        let parsed = [
            makeParsedProject(name: "Track", filePath: "/projects/track.als", plugins: [
                makeParsedPlugin(name: "Serum", type: "vst3", instanceCount: 5),
            ]),
        ]
        let result = try await reconciler.reconcile(parsedProjects: parsed)
        #expect(result.updatedProjects == 1)

        let freshContext = ModelContext(container)
        let projects = try freshContext.fetch(FetchDescriptor<AbletonProject>())
        #expect(projects[0].plugins[0].instanceCount == 5)
    }

    // MARK: - PluginRow usage data tests

    @Test("PluginRow stores projectCount and instanceCount")
    func pluginRowStoresUsageCounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let plugin = Plugin(
            name: "TestPlug",
            bundleIdentifier: "com.test.plug",
            format: .vst3,
            currentVersion: "1.0",
            path: "/Library/Audio/Plug-Ins/VST3/TestPlug.vst3"
        )
        context.insert(plugin)
        try context.save()

        let row = PluginRow(
            plugin: plugin,
            availableVersion: "—",
            hasUpdate: false,
            downloadURL: nil,
            projectCount: 10,
            instanceCount: 25
        )
        #expect(row.projectCount == 10)
        #expect(row.instanceCount == 25)
    }

    @Test("PluginRow with zero usage shows 0 for both counts")
    func pluginRowWithZeroUsage() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let plugin = Plugin(
            name: "UnusedPlug",
            bundleIdentifier: "com.test.unused",
            format: .au,
            currentVersion: "2.0",
            path: "/Library/Audio/Plug-Ins/Components/UnusedPlug.component"
        )
        context.insert(plugin)
        try context.save()

        let row = PluginRow(
            plugin: plugin,
            availableVersion: "—",
            hasUpdate: false,
            downloadURL: nil,
            projectCount: 0,
            instanceCount: 0
        )
        #expect(row.projectCount == 0)
        #expect(row.instanceCount == 0)
    }

    @Test("PluginRow instanceCount can exceed projectCount")
    func pluginRowInstanceCountExceedsProjectCount() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let plugin = Plugin(
            name: "PopularPlug",
            bundleIdentifier: "com.test.popular",
            format: .vst3,
            currentVersion: "3.0",
            path: "/Library/Audio/Plug-Ins/VST3/PopularPlug.vst3"
        )
        context.insert(plugin)
        try context.save()

        // 5 projects, 15 instances = average 3 per project
        let row = PluginRow(
            plugin: plugin,
            availableVersion: "—",
            hasUpdate: false,
            downloadURL: nil,
            projectCount: 5,
            instanceCount: 15
        )
        #expect(row.instanceCount > row.projectCount)
        #expect(row.projectCount == 5)
        #expect(row.instanceCount == 15)
    }
}
