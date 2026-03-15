import Testing
import Foundation
@testable import Pluginventory

@Suite("PluginScanner Tests")
struct PluginScannerTests {

    /// Creates a mock plugin directory with bundles.
    private func createMockPluginDir(
        bundles: [(name: String, ext: String, plist: [String: Any])]
    ) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerTests-\(UUID().uuidString)")

        for bundle in bundles {
            let bundleURL = tempDir.appendingPathComponent("\(bundle.name).\(bundle.ext)")
            let contentsDir = bundleURL.appendingPathComponent("Contents")
            try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)

            let plistURL = contentsDir.appendingPathComponent("Info.plist")
            let data = try PropertyListSerialization.data(fromPropertyList: bundle.plist, format: .xml, options: 0)
            try data.write(to: plistURL)
        }

        return tempDir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Bundle discovery

    @Test("Discovers VST3 bundles in a directory")
    func discoversVST3Bundles() throws {
        let dir = try createMockPluginDir(bundles: [
            (name: "PluginA", ext: "vst3", plist: [
                "CFBundleIdentifier": "com.test.pluginA",
                "CFBundleName": "PluginA"
            ]),
            (name: "PluginB", ext: "vst3", plist: [
                "CFBundleIdentifier": "com.test.pluginB",
                "CFBundleName": "PluginB"
            ])
        ])
        defer { cleanup(dir) }

        let scanner = PluginScanner()
        let bundles = scanner.discoverBundles(in: dir)

        #expect(bundles.count == 2)
        let names = Set(bundles.map { $0.deletingPathExtension().lastPathComponent })
        #expect(names.contains("PluginA"))
        #expect(names.contains("PluginB"))
    }

    @Test("Discovers AU component bundles")
    func discoversAUBundles() throws {
        let dir = try createMockPluginDir(bundles: [
            (name: "MyAU", ext: "component", plist: [
                "CFBundleIdentifier": "com.test.myau",
                "CFBundleName": "MyAU"
            ])
        ])
        defer { cleanup(dir) }

        let scanner = PluginScanner()
        let bundles = scanner.discoverBundles(in: dir)

        #expect(bundles.count == 1)
        #expect(bundles[0].pathExtension == "component")
    }

    @Test("Discovers CLAP bundles")
    func discoversCLAPBundles() throws {
        let dir = try createMockPluginDir(bundles: [
            (name: "MyCLAP", ext: "clap", plist: [
                "CFBundleIdentifier": "com.test.myclap",
                "CFBundleName": "MyCLAP"
            ])
        ])
        defer { cleanup(dir) }

        let scanner = PluginScanner()
        let bundles = scanner.discoverBundles(in: dir)

        #expect(bundles.count == 1)
        #expect(bundles[0].pathExtension == "clap")
    }

    @Test("Ignores non-plugin files")
    func ignoresNonPluginFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Create a regular file (not a plugin bundle)
        let textFile = tempDir.appendingPathComponent("readme.txt")
        try "hello".write(to: textFile, atomically: true, encoding: .utf8)

        // Create a non-plugin directory
        let subdir = tempDir.appendingPathComponent("SomeFolder")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        defer { cleanup(tempDir) }

        let scanner = PluginScanner()
        let bundles = scanner.discoverBundles(in: tempDir)

        #expect(bundles.isEmpty)
    }

    @Test("Returns empty for nonexistent directory")
    func emptyForNonexistentDir() {
        let scanner = PluginScanner()
        let bundles = scanner.discoverBundles(in: URL(fileURLWithPath: "/nonexistent/path"))
        #expect(bundles.isEmpty)
    }

    @Test("Discovers vendor subdirectory bundles")
    func discoversSubdirectoryBundles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerTests-\(UUID().uuidString)")

        // Create a vendor subdirectory with a plugin
        let vendorDir = tempDir.appendingPathComponent("Eventide")
        let bundleURL = vendorDir.appendingPathComponent("H3000.vst3")
        let contentsDir = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)

        let plist: [String: Any] = [
            "CFBundleIdentifier": "com.eventide.h3000",
            "CFBundleName": "H3000"
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contentsDir.appendingPathComponent("Info.plist"))

        defer { cleanup(tempDir) }

        let scanner = PluginScanner()
        let bundles = scanner.discoverBundles(in: tempDir)

        #expect(bundles.count == 1)
        #expect(bundles[0].lastPathComponent == "H3000.vst3")
    }

    // MARK: - Full scan

    @Test("Full scan extracts metadata from all bundles")
    func fullScanExtractsMetadata() async throws {
        let dir = try createMockPluginDir(bundles: [
            (name: "PluginA", ext: "vst3", plist: [
                "CFBundleIdentifier": "com.test.pluginA",
                "CFBundleName": "PluginA",
                "CFBundleShortVersionString": "1.0.0"
            ]),
            (name: "PluginB", ext: "component", plist: [
                "CFBundleIdentifier": "com.test.pluginB",
                "CFBundleName": "PluginB",
                "CFBundleShortVersionString": "2.0.0"
            ])
        ])
        defer { cleanup(dir) }

        let scanner = PluginScanner()
        let result = await scanner.scan(directories: [dir])

        #expect(result.plugins.count == 2)
        #expect(result.errors.isEmpty)
        #expect(result.duration > 0)

        let identifiers = Set(result.plugins.map(\.bundleIdentifier))
        #expect(identifiers.contains("com.test.pluginA"))
        #expect(identifiers.contains("com.test.pluginB"))
    }

    @Test("Scan reports errors for invalid bundles")
    func scanReportsErrors() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerTests-\(UUID().uuidString)")

        // Create a bundle with no Info.plist
        let bundleURL = tempDir.appendingPathComponent("Bad.vst3")
        let contentsDir = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)

        defer { cleanup(tempDir) }

        let scanner = PluginScanner()
        let result = await scanner.scan(directories: [tempDir])

        #expect(result.plugins.isEmpty)
        #expect(result.errors.count == 1)
    }

    @Test("Scan with multiple directories")
    func scanMultipleDirectories() async throws {
        let dir1 = try createMockPluginDir(bundles: [
            (name: "PluginA", ext: "vst3", plist: [
                "CFBundleIdentifier": "com.test.pluginA",
                "CFBundleName": "PluginA",
                "CFBundleShortVersionString": "1.0"
            ])
        ])
        let dir2 = try createMockPluginDir(bundles: [
            (name: "PluginB", ext: "component", plist: [
                "CFBundleIdentifier": "com.test.pluginB",
                "CFBundleName": "PluginB",
                "CFBundleShortVersionString": "2.0"
            ])
        ])
        defer { cleanup(dir1); cleanup(dir2) }

        let scanner = PluginScanner()
        let result = await scanner.scan(directories: [dir1, dir2])

        #expect(result.plugins.count == 2)
    }
}
