import Foundation

/// Checks for new releases of Pluginventory itself via the GitHub Releases API.
actor AppUpdateChecker {

    struct GitHubRelease: Codable {
        let tagName: String
        let htmlUrl: String
        let body: String?
        let publishedAt: String?
        let assets: [Asset]

        struct Asset: Codable {
            let name: String
            let browserDownloadUrl: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadUrl = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlUrl = "html_url"
            case body
            case publishedAt = "published_at"
            case assets
        }
    }

    struct AppUpdate {
        let version: String
        let releaseNotes: String?
        let releasePageURL: URL
        let downloadURL: URL?
        let publishedAt: String?
    }

    /// Abstraction over URLSession for testability.
    protocol URLSessionProtocol: Sendable {
        func data(for request: URLRequest) async throws -> (Data, URLResponse)
    }

    private let session: URLSessionProtocol
    private let apiBaseURL: String

    init(session: URLSessionProtocol = URLSession.shared, apiBaseURL: String? = nil) {
        self.session = session
        self.apiBaseURL = apiBaseURL ?? Constants.AppUpdateConfig.githubAPIBase
    }

    /// Queries GitHub for the latest release and returns an `AppUpdate` if a newer version is available.
    func checkForUpdate(currentVersion: String) async -> AppUpdate? {
        let urlString = "\(apiBaseURL)/repos/\(Constants.AppUpdateConfig.repoOwner)/\(Constants.AppUpdateConfig.repoName)/releases/latest"

        guard let url = URL(string: urlString) else {
            AppLogger.shared.error("Invalid GitHub API URL", category: "appUpdate")
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                AppLogger.shared.error("GitHub API returned status \(code)", category: "appUpdate")
                return nil
            }

            let decoder = JSONDecoder()
            let release = try decoder.decode(GitHubRelease.self, from: data)

            // Strip "v" prefix from tag name for version comparison
            let remoteVersion = release.tagName.normalizedVersion

            guard remoteVersion.isNewerVersion(than: currentVersion) else {
                AppLogger.shared.info("App is up to date (current: \(currentVersion), latest: \(remoteVersion))", category: "appUpdate")
                return nil
            }

            let releasePageURL = URL(string: release.htmlUrl)!
            let pkgAsset = release.assets.first { $0.name.hasSuffix(".pkg") }
            let downloadURL = pkgAsset.flatMap { URL(string: $0.browserDownloadUrl) }

            AppLogger.shared.info("App update available: \(remoteVersion) (current: \(currentVersion))", category: "appUpdate")

            return AppUpdate(
                version: remoteVersion,
                releaseNotes: release.body,
                releasePageURL: releasePageURL,
                downloadURL: downloadURL,
                publishedAt: release.publishedAt
            )
        } catch {
            AppLogger.shared.error("Failed to check for app update: \(error.localizedDescription)", category: "appUpdate")
            return nil
        }
    }
}

extension URLSession: AppUpdateChecker.URLSessionProtocol {}
