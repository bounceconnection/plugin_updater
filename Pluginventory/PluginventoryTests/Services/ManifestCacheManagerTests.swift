import Testing
import Foundation
@testable import Pluginventory

@Suite("ManifestCacheManager Tests")
struct ManifestCacheManagerTests {

    private func makeTempDirectory() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifestCacheTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    @Test("Save and load round-trip preserves entries")
    func saveLoadRoundTrip() async throws {
        let dir = try makeTempDirectory()
        let manager = ManifestCacheManager(cacheDirectory: dir)

        let entries: [String: UpdateManifestEntry] = [
            "com.fabfilter.ProQ3": UpdateManifestEntry(
                bundleIdentifier: "com.fabfilter.ProQ3",
                latestVersion: "3.21",
                downloadURL: "https://fabfilter.com/download",
                releaseNotes: "Bug fixes",
                releaseDate: nil
            ),
            "com.xferrecords.Serum": UpdateManifestEntry(
                bundleIdentifier: "com.xferrecords.Serum",
                latestVersion: "1.35",
                downloadURL: nil,
                releaseNotes: nil,
                releaseDate: nil
            ),
        ]

        await manager.save(entries)
        let loaded = await manager.load()

        #expect(loaded != nil)
        #expect(loaded!.entries.count == 2)
        #expect(loaded!.entries["com.fabfilter.ProQ3"]?.latestVersion == "3.21")
        #expect(loaded!.entries["com.fabfilter.ProQ3"]?.downloadURL == "https://fabfilter.com/download")
        #expect(loaded!.entries["com.xferrecords.Serum"]?.latestVersion == "1.35")
        #expect(loaded!.entries["com.xferrecords.Serum"]?.downloadURL == nil)

        try FileManager.default.removeItem(at: dir)
    }

    @Test("Load from missing file returns nil")
    func loadMissingFile() async throws {
        let dir = try makeTempDirectory()
        let manager = ManifestCacheManager(cacheDirectory: dir)

        let result = await manager.load()
        #expect(result == nil)

        try FileManager.default.removeItem(at: dir)
    }

    @Test("Load from corrupted file returns nil")
    func loadCorruptedFile() async throws {
        let dir = try makeTempDirectory()
        let cacheFile = dir.appendingPathComponent(Constants.CacheFiles.manifestCache)
        try Data("not valid json {{{".utf8).write(to: cacheFile)

        let manager = ManifestCacheManager(cacheDirectory: dir)
        let result = await manager.load()
        #expect(result == nil)

        try FileManager.default.removeItem(at: dir)
    }

    @Test("lastRefreshed is set on save")
    func lastRefreshedIsSet() async throws {
        let dir = try makeTempDirectory()
        let manager = ManifestCacheManager(cacheDirectory: dir)

        let before = Date.now
        await manager.save([:])
        let loaded = await manager.load()

        #expect(loaded != nil)
        // The saved date should be between before and now (with small tolerance)
        #expect(loaded!.lastRefreshed >= before.addingTimeInterval(-1))
        #expect(loaded!.lastRefreshed <= Date.now.addingTimeInterval(1))

        try FileManager.default.removeItem(at: dir)
    }

    @Test("Overwrite existing cache replaces entries")
    func overwriteExistingCache() async throws {
        let dir = try makeTempDirectory()
        let manager = ManifestCacheManager(cacheDirectory: dir)

        let original: [String: UpdateManifestEntry] = [
            "com.old.plugin": UpdateManifestEntry(
                bundleIdentifier: "com.old.plugin",
                latestVersion: "1.0",
                downloadURL: nil,
                releaseNotes: nil,
                releaseDate: nil
            ),
        ]
        await manager.save(original)

        let replacement: [String: UpdateManifestEntry] = [
            "com.new.plugin": UpdateManifestEntry(
                bundleIdentifier: "com.new.plugin",
                latestVersion: "2.0",
                downloadURL: "https://example.com",
                releaseNotes: "New",
                releaseDate: nil
            ),
        ]
        await manager.save(replacement)

        let loaded = await manager.load()
        #expect(loaded != nil)
        #expect(loaded!.entries.count == 1)
        #expect(loaded!.entries["com.new.plugin"]?.latestVersion == "2.0")
        #expect(loaded!.entries["com.old.plugin"] == nil)

        try FileManager.default.removeItem(at: dir)
    }
}
