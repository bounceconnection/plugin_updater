import Testing
import Foundation
@testable import PluginUpdater

@Suite("PluginFormat Tests")
struct PluginFormatTests {

    @Test("Display names are correct")
    func displayNames() {
        #expect(PluginFormat.vst3.displayName == "VST3")
        #expect(PluginFormat.au.displayName == "AU")
        #expect(PluginFormat.clap.displayName == "CLAP")
    }

    @Test("File extensions are correct")
    func fileExtensions() {
        #expect(PluginFormat.vst3.fileExtension == "vst3")
        #expect(PluginFormat.au.fileExtension == "component")
        #expect(PluginFormat.clap.fileExtension == "clap")
    }

    @Test("System directories point to correct paths")
    func systemDirectories() {
        #expect(PluginFormat.vst3.systemDirectory.path == "/Library/Audio/Plug-Ins/VST3")
        #expect(PluginFormat.au.systemDirectory.path == "/Library/Audio/Plug-Ins/Components")
        #expect(PluginFormat.clap.systemDirectory.path == "/Library/Audio/Plug-Ins/CLAP")
    }

    @Test("User directories are under home")
    func userDirectories() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for format in PluginFormat.allCases {
            #expect(format.userDirectory.path.hasPrefix(home.path))
        }
        #expect(PluginFormat.vst3.userDirectory.path.hasSuffix("Library/Audio/Plug-Ins/VST3"))
        #expect(PluginFormat.au.userDirectory.path.hasSuffix("Library/Audio/Plug-Ins/Components"))
        #expect(PluginFormat.clap.userDirectory.path.hasSuffix("Library/Audio/Plug-Ins/CLAP"))
    }

    @Test("allDirectories returns both system and user")
    func allDirectories() {
        for format in PluginFormat.allCases {
            let dirs = format.allDirectories
            #expect(dirs.count == 2)
            #expect(dirs[0] == format.systemDirectory)
            #expect(dirs[1] == format.userDirectory)
        }
    }

    @Test("CaseIterable has all three formats")
    func allCases() {
        #expect(PluginFormat.allCases.count == 3)
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        for format in PluginFormat.allCases {
            let data = try JSONEncoder().encode(format)
            let decoded = try JSONDecoder().decode(PluginFormat.self, from: data)
            #expect(decoded == format)
        }
    }
}
