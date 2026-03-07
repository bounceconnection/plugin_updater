import Foundation

actor ManifestManager {
    private var entriesByBundleID: [String: UpdateManifestEntry] = [:]

    /// Loads the bundled default manifest from app resources.
    func loadBundledManifest() {
        // SPM resource bundle
        guard let url = Bundle.main.url(forResource: "default_manifest", withExtension: "json") else { return }
        load(from: url)
    }

    /// Loads a manifest from a local file URL.
    func load(from url: URL) {
        guard let data = try? Data(contentsOf: url) else { return }
        decode(data)
    }

    /// Fetches a manifest from a remote URL.
    func fetchRemote(from urlString: String) async {
        guard !urlString.isEmpty,
              let url = URL(string: urlString),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return }
        decode(data)
    }

    func latestVersion(for bundleID: String) -> UpdateManifestEntry? {
        entriesByBundleID[bundleID]
    }

    func allEntries() -> [String: UpdateManifestEntry] {
        entriesByBundleID
    }

    private func decode(_ data: Data) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let manifest = try? decoder.decode(UpdateManifest.self, from: data) else { return }
        for entry in manifest.entries {
            entriesByBundleID[entry.bundleIdentifier] = entry
        }
    }
}
