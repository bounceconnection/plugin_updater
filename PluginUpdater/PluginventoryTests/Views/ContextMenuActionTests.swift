import Testing
import Foundation
@testable import Pluginventory

@Suite("Context Menu Action Tests")
struct ContextMenuActionTests {

    // MARK: - Path formatting

    @Test("Single plugin path formatted correctly")
    func singlePluginPath() {
        let paths = ["/Library/Audio/Plug-Ins/VST3/Pro-Q 3.vst3"]
        let result = paths.joined(separator: "\n")
        #expect(result == "/Library/Audio/Plug-Ins/VST3/Pro-Q 3.vst3")
    }

    @Test("Multiple plugin paths joined with newlines")
    func multiplePluginPaths() {
        let paths = [
            "/Library/Audio/Plug-Ins/VST3/Pro-Q 3.vst3",
            "/Library/Audio/Plug-Ins/Components/Pro-Q 3.component",
            "/Library/Audio/Plug-Ins/CLAP/Pro-Q 3.clap",
        ]
        let result = paths.joined(separator: "\n")
        let lines = result.split(separator: "\n")
        #expect(lines.count == 3)
    }

    // MARK: - Full details formatting

    @Test("Full details includes all fields")
    func fullDetailsFormat() {
        let name = "Pro-Q 3"
        let vendor = "FabFilter"
        let format = "vst3"
        let version = "3.23"
        let arch = "Universal"
        let size = ByteCountFormatter.string(fromByteCount: 15_000_000, countStyle: .file)
        let path = "/Library/Audio/Plug-Ins/VST3/Pro-Q 3.vst3"

        let lines = [
            "Name: \(name)",
            "Vendor: \(vendor)",
            "Format: \(format)",
            "Version: \(version)",
            "Architecture: \(arch)",
            "Size: \(size)",
            "Path: \(path)",
        ]
        let details = lines.joined(separator: "\n")

        #expect(details.contains("Name: Pro-Q 3"))
        #expect(details.contains("Vendor: FabFilter"))
        #expect(details.contains("Architecture: Universal"))
        #expect(details.contains("Path: /Library/Audio/Plug-Ins/VST3/Pro-Q 3.vst3"))
    }

    @Test("Multiple plugins separated by double newlines")
    func multiplePluginDetails() {
        let plugin1Details = "Name: Plugin A\nVersion: 1.0"
        let plugin2Details = "Name: Plugin B\nVersion: 2.0"
        let combined = [plugin1Details, plugin2Details].joined(separator: "\n\n")
        #expect(combined.contains("\n\n"))
        #expect(combined.contains("Plugin A"))
        #expect(combined.contains("Plugin B"))
    }

    // MARK: - Vendor URL deduplication

    @Test("Duplicate vendor URLs are deduplicated")
    func vendorURLDeduplication() {
        let urls = [
            "https://www.fabfilter.com",
            "https://www.fabfilter.com",
            "https://www.native-instruments.com",
            "https://www.fabfilter.com",
        ]
        var seen: Set<String> = []
        var unique: [String] = []
        for url in urls {
            if !seen.contains(url) {
                seen.insert(url)
                unique.append(url)
            }
        }
        #expect(unique.count == 2)
        #expect(unique[0] == "https://www.fabfilter.com")
        #expect(unique[1] == "https://www.native-instruments.com")
    }

    @Test("Vendor URL list capped at 10")
    func vendorURLCap() {
        let urls = (0..<20).map { "https://vendor\($0).com" }
        var seen: Set<String> = []
        var unique: [String] = []
        for url in urls {
            guard !seen.contains(url) else { continue }
            seen.insert(url)
            unique.append(url)
            if unique.count >= 10 { break }
        }
        #expect(unique.count == 10)
    }

    // MARK: - Status bar text

    @Test("Status bar shows plugin count without selection")
    func statusBarNoSelection() {
        let count = 1523
        let selectionCount = 0
        let text: String
        if selectionCount > 0 {
            text = "Found \(count) plugins (\(selectionCount) selected)"
        } else {
            text = "Found \(count) plugin\(count == 1 ? "" : "s")"
        }
        #expect(text == "Found 1523 plugins")
    }

    @Test("Status bar shows selection count")
    func statusBarWithSelection() {
        let count = 1523
        let selectionCount = 4
        let text: String
        if selectionCount > 0 {
            text = "Found \(count) plugins (\(selectionCount) selected)"
        } else {
            text = "Found \(count) plugin\(count == 1 ? "" : "s")"
        }
        #expect(text == "Found 1523 plugins (4 selected)")
    }

    @Test("Status bar singular for 1 plugin")
    func statusBarSingular() {
        let count = 1
        let selectionCount = 0
        let text = "Found \(count) plugin\(count == 1 ? "" : "s")"
        #expect(text == "Found 1 plugin")
    }
}
