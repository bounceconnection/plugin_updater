import Foundation

/// Cached manifest with entries and a timestamp for UI display.
struct CachedManifest: Codable {
    let entries: [String: UpdateManifestEntry]
    let lastRefreshed: Date
}

/// Manages reading and writing the manifest cache to disk.
/// Uses a simple JSON file alongside the SwiftData store.
actor ManifestCacheManager {
    private let cacheURL: URL

    init(cacheDirectory: URL? = nil) {
        let dir = cacheDirectory ?? PersistenceController.storeURL.deletingLastPathComponent()
        self.cacheURL = dir.appendingPathComponent(Constants.CacheFiles.manifestCache)
    }

    /// Loads cached manifest entries from disk. Returns nil if the file is missing or corrupted.
    func load() -> CachedManifest? {
        guard let data = try? Data(contentsOf: cacheURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CachedManifest.self, from: data)
    }

    /// Saves the current manifest entries to disk with the current timestamp.
    func save(_ entries: [String: UpdateManifestEntry]) {
        let cached = CachedManifest(entries: entries, lastRefreshed: Date.now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(cached) else { return }
        try? data.write(to: cacheURL, options: .atomic)
    }
}
