import Foundation
import SwiftData

/// Reconciles parsed Ableton project data against the SwiftData store.
@ModelActor
actor ProjectReconciler {

    struct ReconciliationResult: Sendable {
        let newProjects: Int
        let updatedProjects: Int
        let removedProjects: Int
        let skippedProjects: Int
        let totalProcessed: Int
    }

    // Cached state across batches — built once per scan, reused for every batch.
    private var existingByPath: [String: AbletonProject]?
    private var pluginIndex: PluginMatcher.PluginIndex?
    private var matchCache: [AbletonProjectParser.ParsedPlugin: PluginMatcher.MatchResult] = [:]

    /// Builds caches that persist across reconcile() calls within a scan.
    /// Call once before the first batch.
    func prepareForScan() throws {
        let projectDescriptor = FetchDescriptor<AbletonProject>()
        let existingProjects = try modelContext.fetch(projectDescriptor)
        var byPath: [String: AbletonProject] = [:]
        byPath.reserveCapacity(existingProjects.count)
        for project in existingProjects {
            byPath[project.filePath] = project
        }
        existingByPath = byPath

        let pluginDescriptor = FetchDescriptor<Plugin>(
            predicate: #Predicate { !$0.isRemoved }
        )
        let installedPlugins = try modelContext.fetch(pluginDescriptor)
        pluginIndex = PluginMatcher.PluginIndex(plugins: installedPlugins)
        matchCache = [:]
    }

    /// Clears cached state after a scan completes.
    func finishScan() {
        existingByPath = nil
        pluginIndex = nil
        matchCache = [:]
    }

    /// Reconciles parsed Ableton projects against the SwiftData store.
    func reconcile(
        parsedProjects: [AbletonProjectParser.ParsedProject],
        fullScan: Bool = true
    ) throws -> ReconciliationResult {
        // Build caches on first call if prepareForScan() wasn't called
        if existingByPath == nil || pluginIndex == nil {
            try prepareForScan()
        }
        guard let existingByPath = existingByPath,
              let pluginIndex = pluginIndex else {
            // Should never happen after prepareForScan()
            return ReconciliationResult(newProjects: 0, updatedProjects: 0, removedProjects: 0, skippedProjects: 0, totalProcessed: 0)
        }

        var seenPaths: Set<String> = []
        var newCount = 0
        var updatedCount = 0
        var skippedCount = 0
        var matchedCount = 0
        var unmatchedCount = 0

        for parsed in parsedProjects {
            seenPaths.insert(parsed.filePath)

            if let existing = existingByPath[parsed.filePath] {
                // Skip unchanged projects — same lastModified means plugins haven't changed
                if existing.lastModified == parsed.lastModified && !existing.isRemoved {
                    existing.lastScannedDate = .now
                    skippedCount += 1
                    continue
                }

                existing.name = parsed.name
                existing.lastModified = parsed.lastModified
                existing.fileSize = parsed.fileSize
                existing.abletonVersion = parsed.abletonVersion
                existing.lastScannedDate = .now
                existing.isRemoved = false

                for plugin in existing.plugins {
                    modelContext.delete(plugin)
                }
                existing.plugins = []

                for parsedPlugin in parsed.plugins {
                    let projectPlugin = createProjectPlugin(
                        from: parsedPlugin,
                        index: pluginIndex,
                        cache: &matchCache
                    )
                    existing.plugins.append(projectPlugin)
                    if projectPlugin.isInstalled { matchedCount += 1 } else { unmatchedCount += 1 }
                }

                updatedCount += 1
            } else {
                let project = AbletonProject(
                    filePath: parsed.filePath,
                    name: parsed.name,
                    lastModified: parsed.lastModified,
                    fileSize: parsed.fileSize,
                    abletonVersion: parsed.abletonVersion,
                    lastScannedDate: .now
                )
                modelContext.insert(project)
                // Update the cache so subsequent batches see this project
                self.existingByPath?[parsed.filePath] = project

                for parsedPlugin in parsed.plugins {
                    let projectPlugin = createProjectPlugin(
                        from: parsedPlugin,
                        index: pluginIndex,
                        cache: &matchCache
                    )
                    project.plugins.append(projectPlugin)
                    if projectPlugin.isInstalled { matchedCount += 1 } else { unmatchedCount += 1 }
                }

                newCount += 1
            }
        }

        var removedCount = 0
        if fullScan {
            for (path, project) in existingByPath
                where !seenPaths.contains(path) && !project.isRemoved {
                project.isRemoved = true
                removedCount += 1
            }
        }

        try modelContext.save()

        AppLogger.shared.info(
            "Reconciled \(parsedProjects.count) projects — \(matchedCount) matched, \(unmatchedCount) unmatched, \(newCount) new, \(updatedCount) updated, \(skippedCount) unchanged, \(removedCount) removed",
            category: "projectScan"
        )

        return ReconciliationResult(
            newProjects: newCount,
            updatedProjects: updatedCount,
            removedProjects: removedCount,
            skippedProjects: skippedCount,
            totalProcessed: parsedProjects.count
        )
    }

    /// Marks projects whose paths are not in `scannedPaths` as removed.
    /// Used after streaming scan completes to sweep missing projects.
    func markMissingProjects(scannedPaths: Set<String>) throws -> Int {
        let descriptor = FetchDescriptor<AbletonProject>()
        let existingProjects = try modelContext.fetch(descriptor)

        var removedCount = 0
        for project in existingProjects
            where !scannedPaths.contains(project.filePath) && !project.isRemoved {
            project.isRemoved = true
            removedCount += 1
        }

        try modelContext.save()
        return removedCount
    }

    /// Re-runs plugin matching for all projects against current installed plugins.
    /// Call after a plugin scan completes to update isInstalled flags.
    func refreshPluginMatching() throws {
        let projectDescriptor = FetchDescriptor<AbletonProject>(
            predicate: #Predicate { !$0.isRemoved }
        )
        let projects = try modelContext.fetch(projectDescriptor)

        let pluginDescriptor = FetchDescriptor<Plugin>(
            predicate: #Predicate { !$0.isRemoved }
        )
        let installedPlugins = try modelContext.fetch(pluginDescriptor)
        let index = PluginMatcher.PluginIndex(plugins: installedPlugins)
        var cache: [AbletonProjectParser.ParsedPlugin: PluginMatcher.MatchResult] = [:]

        for project in projects {
            for projectPlugin in project.plugins {
                let parsed = AbletonProjectParser.ParsedPlugin(
                    pluginName: projectPlugin.pluginName,
                    pluginType: projectPlugin.pluginType,
                    auComponentType: projectPlugin.auComponentType,
                    auComponentSubType: projectPlugin.auComponentSubType,
                    auComponentManufacturer: projectPlugin.auComponentManufacturer,
                    vst3TUID: projectPlugin.vst3TUID,
                    vendorName: projectPlugin.vendorName
                )
                let result: PluginMatcher.MatchResult
                if let cached = cache[parsed] {
                    result = cached
                } else {
                    result = PluginMatcher.match(parsed, index: index)
                    cache[parsed] = result
                }
                projectPlugin.isInstalled = result.isInstalled
                projectPlugin.matchedPluginID = result.matchedPluginID
            }
        }

        try modelContext.save()
    }

    // MARK: - Private

    private func createProjectPlugin(
        from parsed: AbletonProjectParser.ParsedPlugin,
        index: PluginMatcher.PluginIndex,
        cache: inout [AbletonProjectParser.ParsedPlugin: PluginMatcher.MatchResult]
    ) -> AbletonProjectPlugin {
        let matchResult: PluginMatcher.MatchResult
        if let cached = cache[parsed] {
            matchResult = cached
        } else {
            matchResult = PluginMatcher.match(parsed, index: index)
            cache[parsed] = matchResult
        }

        return AbletonProjectPlugin(
            pluginName: parsed.pluginName,
            pluginType: parsed.pluginType,
            auComponentType: parsed.auComponentType,
            auComponentSubType: parsed.auComponentSubType,
            auComponentManufacturer: parsed.auComponentManufacturer,
            vst3TUID: parsed.vst3TUID,
            vendorName: parsed.vendorName,
            matchedPluginID: matchResult.matchedPluginID,
            isInstalled: matchResult.isInstalled,
            instanceCount: parsed.instanceCount
        )
    }
}
