import Testing
import Foundation
@testable import PluginUpdater

@Suite("BundleMetadataExtractor Tests")
struct BundleMetadataExtractorTests {

    /// Creates a temporary mock plugin bundle with the given Info.plist contents.
    private func createMockBundle(
        name: String,
        extension ext: String,
        plist: [String: Any]
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginUpdaterTests-\(UUID().uuidString)")
        let bundleURL = tempDir.appendingPathComponent("\(name).\(ext)")
        let contentsDir = bundleURL.appendingPathComponent("Contents")

        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)

        let plistURL = contentsDir.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: plistURL)

        return bundleURL
    }

    private func cleanup(_ url: URL) {
        // Remove the temp directory (parent of the bundle)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Basic extraction

    @Test("Extracts metadata from VST3 bundle")
    func extractsVST3Metadata() throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.fabfilter.Pro-Q.3",
            "CFBundleName": "Pro-Q 3",
            "CFBundleShortVersionString": "3.23",
            "NSHumanReadableCopyright": "Copyright 2024 FabFilter"
        ]

        let bundleURL = try createMockBundle(name: "Pro-Q 3", extension: "vst3", plist: plist)
        defer { cleanup(bundleURL) }

        let metadata = try BundleMetadataExtractor.extract(from: bundleURL)

        #expect(metadata.bundleIdentifier == "com.fabfilter.Pro-Q.3")
        #expect(metadata.name == "Pro-Q 3")
        #expect(metadata.version == "3.23")
        #expect(metadata.format == .vst3)
    }

    @Test("Extracts metadata from AU component")
    func extractsAUMetadata() throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.fabfilter.Pro-Q.3.AU",
            "CFBundleName": "Pro-Q 3",
            "CFBundleShortVersionString": "3.23",
            "AudioComponents": [
                [
                    "name": "FabFilter: Pro-Q 3",
                    "manufacturer": "FabF",
                    "type": "aufx",
                    "subtype": "FQ3p"
                ]
            ]
        ]

        let bundleURL = try createMockBundle(name: "Pro-Q 3", extension: "component", plist: plist)
        defer { cleanup(bundleURL) }

        let metadata = try BundleMetadataExtractor.extract(from: bundleURL)

        #expect(metadata.format == .au)
        #expect(metadata.vendorName == "FabFilter")
    }

    @Test("Extracts metadata from CLAP bundle")
    func extractsCLAPMetadata() throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.example.TestPlugin",
            "CFBundleName": "TestPlugin",
            "CFBundleShortVersionString": "1.0.0",
            "NSHumanReadableCopyright": "Copyright 2024 Example"
        ]

        let bundleURL = try createMockBundle(name: "TestPlugin", extension: "clap", plist: plist)
        defer { cleanup(bundleURL) }

        let metadata = try BundleMetadataExtractor.extract(from: bundleURL)

        #expect(metadata.format == .clap)
        #expect(metadata.bundleIdentifier == "com.example.TestPlugin")
    }

    // MARK: - AU vendor resolution

    @Test("AU vendor extracted from component name field, not manufacturer code")
    func auVendorFromNameField() throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.ValhallaDSP.ValhallaSupermassive",
            "CFBundleName": "ValhallaSupermassive",
            "CFBundleShortVersionString": "2.5.0",
            "AudioComponents": [
                [
                    "name": "Valhalla DSP, LLC: ValhallaSupermassive",
                    "manufacturer": "oDin",
                    "type": "aufx",
                    "subtype": "sMas"
                ]
            ]
        ]

        let bundleURL = try createMockBundle(name: "ValhallaSupermassive", extension: "component", plist: plist)
        defer { cleanup(bundleURL) }

        let metadata = try BundleMetadataExtractor.extract(from: bundleURL)

        // Should use "Valhalla DSP, LLC" from name field, not "oDin"
        #expect(metadata.vendorName == "Valhalla DSP, LLC")
    }

    @Test("AU vendor falls through 4-char manufacturer code")
    func auFallsThrough4CharCode() throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.testvendor.TestPlugin",
            "CFBundleName": "TestPlugin",
            "CFBundleShortVersionString": "1.0",
            "NSHumanReadableCopyright": "Copyright 2024 TestVendor",
            "AudioComponents": [
                [
                    "manufacturer": "tVnd",
                    "type": "aufx"
                ]
            ]
        ]

        let bundleURL = try createMockBundle(name: "TestPlugin", extension: "component", plist: plist)
        defer { cleanup(bundleURL) }

        let metadata = try BundleMetadataExtractor.extract(from: bundleURL)

        // 4-char code should be skipped, falls to copyright
        #expect(metadata.vendorName == "TestVendor")
    }

    // MARK: - Version extraction

    @Test("Prefers CFBundleShortVersionString over CFBundleVersion")
    func prefersShortVersion() throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.test.plugin",
            "CFBundleName": "Test",
            "CFBundleShortVersionString": "2.0.0",
            "CFBundleVersion": "12345"
        ]

        let bundleURL = try createMockBundle(name: "Test", extension: "vst3", plist: plist)
        defer { cleanup(bundleURL) }

        let metadata = try BundleMetadataExtractor.extract(from: bundleURL)
        #expect(metadata.version == "2.0.0")
    }

    @Test("Falls back to CFBundleVersion when short version missing")
    func fallsBackToBundleVersion() throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.test.plugin",
            "CFBundleName": "Test",
            "CFBundleVersion": "42"
        ]

        let bundleURL = try createMockBundle(name: "Test", extension: "vst3", plist: plist)
        defer { cleanup(bundleURL) }

        let metadata = try BundleMetadataExtractor.extract(from: bundleURL)
        #expect(metadata.version == "42")
    }

    @Test("Returns 0.0.0 when no version present")
    func defaultVersion() throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.test.plugin",
            "CFBundleName": "Test"
        ]

        let bundleURL = try createMockBundle(name: "Test", extension: "vst3", plist: plist)
        defer { cleanup(bundleURL) }

        let metadata = try BundleMetadataExtractor.extract(from: bundleURL)
        #expect(metadata.version == "0.0.0")
    }

    // MARK: - Name extraction

    @Test("Prefers CFBundleDisplayName over CFBundleName")
    func prefersDisplayName() throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.test.plugin",
            "CFBundleDisplayName": "My Display Name",
            "CFBundleName": "BundleName"
        ]

        let bundleURL = try createMockBundle(name: "Filename", extension: "vst3", plist: plist)
        defer { cleanup(bundleURL) }

        let metadata = try BundleMetadataExtractor.extract(from: bundleURL)
        #expect(metadata.name == "My Display Name")
    }

    @Test("Falls back to filename when no plist names")
    func fallsBackToFilename() throws {
        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.test.plugin"
        ]

        let bundleURL = try createMockBundle(name: "MyPlugin", extension: "vst3", plist: plist)
        defer { cleanup(bundleURL) }

        let metadata = try BundleMetadataExtractor.extract(from: bundleURL)
        #expect(metadata.name == "MyPlugin")
    }

    // MARK: - Error cases

    @Test("Throws when no Info.plist exists")
    func throwsNoPlist() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PluginUpdaterTests-\(UUID().uuidString)")
        let bundleURL = tempDir.appendingPathComponent("NoInfo.vst3")
        let contentsDir = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        #expect(throws: BundleMetadataExtractor.ExtractionError.self) {
            _ = try BundleMetadataExtractor.extract(from: bundleURL)
        }
    }

    @Test("Throws when no bundle identifier")
    func throwsNoBundleID() throws {
        let plist: [String: Any] = [
            "CFBundleName": "Test"
        ]

        let bundleURL = try createMockBundle(name: "Test", extension: "vst3", plist: plist)
        defer { cleanup(bundleURL) }

        #expect(throws: BundleMetadataExtractor.ExtractionError.self) {
            _ = try BundleMetadataExtractor.extract(from: bundleURL)
        }
    }
}
