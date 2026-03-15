import Testing
import Foundation
import SwiftData
@testable import PluginUpdater

@Suite("PluginMatcher Tests")
struct PluginMatcherTests {

    private func makeContainer() throws -> ModelContainer {
        try PersistenceController.makeContainer(inMemory: true)
    }

    private func insertPlugin(
        name: String,
        format: PluginFormat,
        vendor: String = "TestVendor",
        into context: ModelContext
    ) -> Plugin {
        let plugin = Plugin(
            name: name,
            bundleIdentifier: "com.test.\(name.lowercased().replacingOccurrences(of: " ", with: "-"))",
            format: format,
            currentVersion: "1.0.0",
            path: "/Library/Audio/Plug-Ins/\(format.fileExtension)/\(name).\(format.fileExtension)",
            vendorName: vendor
        )
        context.insert(plugin)
        return plugin
    }

    private func makeParsed(
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

    private func fetchPlugins(from context: ModelContext) throws -> [Plugin] {
        try context.fetch(FetchDescriptor<Plugin>())
    }

    @Test("Matches AU by exact name")
    func matchesAUByExactName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Pro-L 2", format: .au, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "Pro-L 2", type: "au"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == true)
    }

    @Test("Matches VST3 by exact name")
    func matchesVST3ByExactName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Serum 2", format: .vst3, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "Serum 2", type: "vst3"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == true)
    }

    @Test("Matches VST2 by exact name")
    func matchesVST2ByExactName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Duck", format: .vst2, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "Duck", type: "vst2"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == true)
    }

    @Test("Matches case insensitive")
    func matchesCaseInsensitive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Pro-L 2", format: .au, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "pro-l 2", type: "au"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == true)
    }

    @Test("Matches cross-format")
    func matchesCrossFormat() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Serum 2", format: .au, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "Serum 2", type: "vst3"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == true)
    }

    @Test("Matches by contains")
    func matchesByContains() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "FabFilter Pro-L 2", format: .au, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "Pro-L 2", type: "au"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == true)
    }

    @Test("Matches by reverse contains")
    func matchesByReverseContains() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Pro-L 2", format: .au, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "FabFilter Pro-L 2", type: "au"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == true)
    }

    @Test("Returns not installed when no match")
    func returnsNotInstalledWhenNoMatch() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Pro-L 2", format: .au, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "NonExistentPlugin", type: "au"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == false)
    }

    // MARK: - Fuzzy Matching Tests

    @Test("Matches stripped version suffix")
    func matchesStrippedVersionSuffix() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Phoscyon", format: .au, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "Phoscyon 2", type: "au"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == true)
    }

    @Test("Matches normalized alphanumeric")
    func matchesNormalizedAlphanumeric() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Filter Freak 1", format: .vst3, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "FilterFreak1", type: "vst3"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == true)
    }

    @Test("Matches vendor-scoped AU fuzzy")
    func matchesVendorScopedFuzzy() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Phoscyon", format: .au, vendor: "D16", into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "Phoscyon 2", type: "au", vendor: "D16"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == true)
    }

    @Test("Does not fuzzy match unrelated plugin")
    func doesNotFuzzyMatchUnrelatedPlugin() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Pro-Q 2", format: .au, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let result = PluginMatcher.match(
            makeParsed(name: "Pro-L 2", type: "au"),
            installedPlugins: plugins
        )
        #expect(result.isInstalled == false)
    }

    // MARK: - PluginIndex Tests

    @Test("PluginIndex produces same results as backward-compat overload")
    func pluginIndexProducesSameResults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Serum", format: .vst3, into: context)
        let _ = insertPlugin(name: "Pro-L 2", format: .au, vendor: "FabFilter", into: context)
        let _ = insertPlugin(name: "Filter Freak 1", format: .vst3, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let index = PluginMatcher.PluginIndex(plugins: plugins)

        let testCases: [AbletonProjectParser.ParsedPlugin] = [
            makeParsed(name: "Serum", type: "vst3"),
            makeParsed(name: "Pro-L 2", type: "au"),
            makeParsed(name: "FilterFreak1", type: "vst3"),
            makeParsed(name: "NonExistent", type: "au"),
        ]

        for parsed in testCases {
            let linearResult = PluginMatcher.match(parsed, installedPlugins: plugins)
            let indexResult = PluginMatcher.match(parsed, index: index)
            #expect(
                linearResult.isInstalled == indexResult.isInstalled,
                "Mismatch for \(parsed.pluginName): linear=\(linearResult.isInstalled), index=\(indexResult.isInstalled)"
            )
        }
    }

    @Test("Match cache returns consistent results")
    func matchCacheReturnsConsistentResults() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Serum", format: .vst3, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let index = PluginMatcher.PluginIndex(plugins: plugins)

        let parsed = makeParsed(name: "Serum", type: "vst3")
        let first = PluginMatcher.match(parsed, index: index)
        let second = PluginMatcher.match(parsed, index: index)

        #expect(first.isInstalled == second.isInstalled)
        #expect(first.matchedPluginID == second.matchedPluginID)
    }

    @Test("PluginIndex excludes removed plugins")
    func pluginIndexExcludesRemovedPlugins() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let plugin = insertPlugin(name: "RemovedSynth", format: .vst3, into: context)
        plugin.isRemoved = true
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let index = PluginMatcher.PluginIndex(plugins: plugins)

        let result = PluginMatcher.match(
            makeParsed(name: "RemovedSynth", type: "vst3"),
            index: index
        )
        #expect(result.isInstalled == false)
    }

    @Test("PluginIndex with empty plugin list returns no matches")
    func pluginIndexEmptyReturnsNoMatches() throws {
        let index = PluginMatcher.PluginIndex(plugins: [])
        let result = PluginMatcher.match(
            makeParsed(name: "Anything", type: "au"),
            index: index
        )
        #expect(result.isInstalled == false)
        #expect(result.matchedPluginID == nil)
    }

    @Test("PluginIndex handles unknown plugin type")
    func pluginIndexUnknownType() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let _ = insertPlugin(name: "Serum", format: .vst3, into: context)
        try context.save()
        let plugins = try fetchPlugins(from: context)
        let index = PluginMatcher.PluginIndex(plugins: plugins)

        let result = PluginMatcher.match(
            makeParsed(name: "Serum", type: "unknown_format"),
            index: index
        )
        #expect(result.isInstalled == false)
    }
}
