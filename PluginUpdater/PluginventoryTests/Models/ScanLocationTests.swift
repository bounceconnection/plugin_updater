import Testing
import Foundation
import SwiftData
@testable import Pluginventory

@Suite("ScanLocation Tests")
struct ScanLocationTests {

    @Test("ScanLocation stores path and format")
    func basicProperties() {
        let loc = ScanLocation(
            path: "/Library/Audio/Plug-Ins/VST3",
            format: .vst3,
            isDefault: true
        )
        #expect(loc.path == "/Library/Audio/Plug-Ins/VST3")
        #expect(loc.format == .vst3)
        #expect(loc.isDefault == true)
        #expect(loc.isEnabled == true)
    }

    @Test("ScanLocation url for absolute path")
    func absolutePathURL() {
        let loc = ScanLocation(
            path: "/Library/Audio/Plug-Ins/VST3",
            format: .vst3
        )
        #expect(loc.url.path == "/Library/Audio/Plug-Ins/VST3")
    }

    @Test("ScanLocation url expands tilde")
    func tildeExpansion() {
        let loc = ScanLocation(
            path: "~/Library/Audio/Plug-Ins/VST3",
            format: .vst3
        )
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(loc.url.path.hasPrefix(home))
        #expect(loc.url.path.hasSuffix("Library/Audio/Plug-Ins/VST3"))
    }

    @Test("ScanLocation persists in SwiftData")
    func persistence() throws {
        let container = try PersistenceController.makeContainer(inMemory: true)
        let context = ModelContext(container)

        let loc = ScanLocation(
            path: "/custom/path",
            format: .clap,
            isDefault: false,
            isEnabled: false
        )
        context.insert(loc)
        try context.save()

        let descriptor = FetchDescriptor<ScanLocation>()
        let fetched = try context.fetch(descriptor)
        #expect(fetched.count == 1)
        #expect(fetched[0].path == "/custom/path")
        #expect(fetched[0].format == .clap)
        #expect(fetched[0].isDefault == false)
        #expect(fetched[0].isEnabled == false)
    }
}
