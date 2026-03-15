import Foundation

struct UpdateManifestEntry: Codable, Identifiable {
    var id: String { bundleIdentifier }

    let bundleIdentifier: String
    let latestVersion: String
    let downloadURL: String?
    let releaseNotes: String?
    let releaseDate: Date?

    enum CodingKeys: String, CodingKey {
        case bundleIdentifier = "bundle_identifier"
        case latestVersion = "latest_version"
        case downloadURL = "download_url"
        case releaseNotes = "release_notes"
        case releaseDate = "release_date"
    }
}

struct UpdateManifest: Codable {
    let version: Int
    let lastUpdated: Date
    let entries: [UpdateManifestEntry]

    enum CodingKeys: String, CodingKey {
        case version
        case lastUpdated = "last_updated"
        case entries
    }
}
