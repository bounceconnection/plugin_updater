import Testing
import Foundation
@testable import Pluginventory

@Suite("URL+PluginBundle Tests")
struct URLExtensionTests {

    @Test("isPluginBundle detects VST3")
    func detectsVST3() {
        let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3/Serum.vst3")
        #expect(url.isPluginBundle == true)
    }

    @Test("isPluginBundle detects AU component")
    func detectsAU() {
        let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/Components/Kontakt.component")
        #expect(url.isPluginBundle == true)
    }

    @Test("isPluginBundle detects CLAP")
    func detectsCLAP() {
        let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/CLAP/Surge.clap")
        #expect(url.isPluginBundle == true)
    }

    @Test("isPluginBundle rejects non-plugin")
    func rejectsNonPlugin() {
        let url = URL(fileURLWithPath: "/Library/Some/Other/file.txt")
        #expect(url.isPluginBundle == false)
    }

    @Test("isPluginBundle is case-insensitive")
    func caseInsensitive() {
        let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3/Plugin.VST3")
        #expect(url.isPluginBundle == true)
    }

    @Test("pluginFormat returns correct format for VST3")
    func formatVST3() {
        let url = URL(fileURLWithPath: "/path/to/Plugin.vst3")
        #expect(url.pluginFormat == .vst3)
    }

    @Test("pluginFormat returns correct format for AU")
    func formatAU() {
        let url = URL(fileURLWithPath: "/path/to/Plugin.component")
        #expect(url.pluginFormat == .au)
    }

    @Test("pluginFormat returns correct format for CLAP")
    func formatCLAP() {
        let url = URL(fileURLWithPath: "/path/to/Plugin.clap")
        #expect(url.pluginFormat == .clap)
    }

    @Test("pluginFormat returns nil for non-plugin")
    func formatNil() {
        let url = URL(fileURLWithPath: "/path/to/file.app")
        #expect(url.pluginFormat == nil)
    }

    @Test("infoPlistURL appends Contents/Info.plist")
    func infoPlist() {
        let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3/Serum.vst3")
        #expect(url.infoPlistURL.path.hasSuffix("Contents/Info.plist"))
    }

    @Test("parentDirectoryName returns parent folder name")
    func parentDirectory() {
        let url = URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3/Eventide/H3000.vst3")
        #expect(url.parentDirectoryName == "Eventide")
    }
}
