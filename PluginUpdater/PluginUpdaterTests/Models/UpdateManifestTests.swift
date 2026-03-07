import Testing
import Foundation
@testable import PluginUpdater

@Suite("UpdateManifest Tests")
struct UpdateManifestTests {

    @Test("Decode manifest entry from JSON")
    func decodeEntry() throws {
        let json = """
        {
            "bundle_identifier": "com.fabfilter.ProQ3",
            "latest_version": "3.21",
            "download_url": "https://www.fabfilter.com/download",
            "release_notes": "Bug fixes",
            "release_date": "2024-06-15T00:00:00Z"
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(UpdateManifestEntry.self, from: Data(json.utf8))

        #expect(entry.bundleIdentifier == "com.fabfilter.ProQ3")
        #expect(entry.latestVersion == "3.21")
        #expect(entry.downloadURL == "https://www.fabfilter.com/download")
        #expect(entry.releaseNotes == "Bug fixes")
        #expect(entry.releaseDate != nil)
    }

    @Test("Decode manifest entry with optional fields nil")
    func decodeEntryOptionals() throws {
        let json = """
        {
            "bundle_identifier": "com.test.plugin",
            "latest_version": "1.0"
        }
        """
        let entry = try JSONDecoder().decode(UpdateManifestEntry.self, from: Data(json.utf8))

        #expect(entry.bundleIdentifier == "com.test.plugin")
        #expect(entry.latestVersion == "1.0")
        #expect(entry.downloadURL == nil)
        #expect(entry.releaseNotes == nil)
        #expect(entry.releaseDate == nil)
    }

    @Test("Decode full manifest")
    func decodeFullManifest() throws {
        let json = """
        {
            "version": 1,
            "last_updated": "2024-01-15T12:00:00Z",
            "entries": [
                {
                    "bundle_identifier": "com.fabfilter.ProQ3",
                    "latest_version": "3.21"
                },
                {
                    "bundle_identifier": "com.xferrecords.Serum",
                    "latest_version": "1.35"
                }
            ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(UpdateManifest.self, from: Data(json.utf8))

        #expect(manifest.version == 1)
        #expect(manifest.entries.count == 2)
        #expect(manifest.entries[0].bundleIdentifier == "com.fabfilter.ProQ3")
        #expect(manifest.entries[1].bundleIdentifier == "com.xferrecords.Serum")
    }

    @Test("Encode and decode manifest round-trip")
    func encodeDecode() throws {
        let entry = UpdateManifestEntry(
            bundleIdentifier: "com.test.roundtrip",
            latestVersion: "2.0.1",
            downloadURL: "https://example.com",
            releaseNotes: "New feature",
            releaseDate: nil
        )
        let manifest = UpdateManifest(
            version: 1,
            lastUpdated: Date(timeIntervalSince1970: 0),
            entries: [entry]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(manifest)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UpdateManifest.self, from: data)

        #expect(decoded.version == 1)
        #expect(decoded.entries.count == 1)
        #expect(decoded.entries[0].bundleIdentifier == "com.test.roundtrip")
        #expect(decoded.entries[0].latestVersion == "2.0.1")
    }

    @Test("UpdateManifestEntry id is bundleIdentifier")
    func entryId() {
        let entry = UpdateManifestEntry(
            bundleIdentifier: "com.example.test",
            latestVersion: "1.0",
            downloadURL: nil,
            releaseNotes: nil,
            releaseDate: nil
        )
        #expect(entry.id == "com.example.test")
    }
}
