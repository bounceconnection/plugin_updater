import Foundation

/// Checks for available plugin updates by querying the Homebrew Formulae API.
/// Uses a bundled mapping of plugin bundle ID prefixes to Homebrew cask names.
actor VersionChecker {

    struct CaskMapping: Codable {
        let bundleIDPrefix: String
        let cask: String

        enum CodingKeys: String, CodingKey {
            case bundleIDPrefix = "bundle_id_prefix"
            case cask
        }
    }

    struct VendorURL: Codable {
        let bundleIDPrefix: String
        let url: String

        enum CodingKeys: String, CodingKey {
            case bundleIDPrefix = "bundle_id_prefix"
            case url
        }
    }

    private var mappings: [CaskMapping] = []
    private var vendorURLs: [VendorURL] = []

    func loadMappings() {
        if let url = Bundle.main.url(forResource: "cask_mappings", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([CaskMapping].self, from: data) {
            mappings = decoded
        }

        if let url = Bundle.main.url(forResource: "vendor_urls", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([VendorURL].self, from: data) {
            vendorURLs = decoded
        }
    }

    /// Returns the vendor website URL for a given bundle ID, if known.
    func vendorURL(for bundleID: String) -> String? {
        vendorURLs.first(where: { bundleID.hasPrefix($0.bundleIDPrefix) })?.url
    }

    /// Given a dictionary of [bundleID: installedVersion], queries the Homebrew API
    /// for any plugins that have a known cask mapping and returns available versions.
    func checkForUpdates(installedPlugins: [String: String]) async -> [String: UpdateManifestEntry] {
        guard !mappings.isEmpty else { return [:] }

        // Match plugins to casks
        var caskToPlugins: [String: [(bundleID: String, installed: String)]] = [:]
        for (bundleID, version) in installedPlugins {
            if let mapping = mappings.first(where: { bundleID.hasPrefix($0.bundleIDPrefix) }) {
                caskToPlugins[mapping.cask, default: []].append((bundleID, version))
            }
        }

        guard !caskToPlugins.isEmpty else { return [:] }

        // Fetch all cask versions in parallel
        var results: [String: UpdateManifestEntry] = [:]

        await withTaskGroup(of: (String, CaskAPIResponse?).self) { group in
            for cask in caskToPlugins.keys {
                group.addTask {
                    let response = await self.fetchCaskInfo(cask)
                    return (cask, response)
                }
            }

            for await (cask, response) in group {
                guard let response else { continue }
                for plugin in caskToPlugins[cask] ?? [] {
                    results[plugin.bundleID] = UpdateManifestEntry(
                        bundleIdentifier: plugin.bundleID,
                        latestVersion: response.version,
                        downloadURL: response.url ?? response.homepage,
                        releaseNotes: nil,
                        releaseDate: nil
                    )
                }
            }
        }

        return results
    }

    // MARK: - Homebrew API

    private struct CaskAPIResponse: Codable {
        let token: String
        let version: String
        let url: String?
        let homepage: String?
    }

    private func fetchCaskInfo(_ cask: String) async -> CaskAPIResponse? {
        guard let url = URL(string: "https://formulae.brew.sh/api/cask/\(cask).json") else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try JSONDecoder().decode(CaskAPIResponse.self, from: data)
        } catch {
            return nil
        }
    }
}
