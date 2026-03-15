import Testing
import Foundation
@testable import Pluginventory

@Suite("PluginFormat Tests")
struct PluginFormatTests {

    @Test("Display names are correct")
    func displayNames() {
        #expect(PluginFormat.au.displayName == "AU")
        #expect(PluginFormat.clap.displayName == "CLAP")
        #expect(PluginFormat.vst2.displayName == "VST2")
        #expect(PluginFormat.vst3.displayName == "VST3")
    }

    @Test("File extensions are correct")
    func fileExtensions() {
        #expect(PluginFormat.au.fileExtension == "component")
        #expect(PluginFormat.clap.fileExtension == "clap")
        #expect(PluginFormat.vst2.fileExtension == "vst")
        #expect(PluginFormat.vst3.fileExtension == "vst3")
    }

    @Test("System directories point to correct paths")
    func systemDirectories() {
        #expect(PluginFormat.au.systemDirectory.path == "/Library/Audio/Plug-Ins/Components")
        #expect(PluginFormat.clap.systemDirectory.path == "/Library/Audio/Plug-Ins/CLAP")
        #expect(PluginFormat.vst2.systemDirectory.path == "/Library/Audio/Plug-Ins/VST")
        #expect(PluginFormat.vst3.systemDirectory.path == "/Library/Audio/Plug-Ins/VST3")
    }

    @Test("CaseIterable has all four formats")
    func allCases() {
        #expect(PluginFormat.allCases.count == 4)
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
