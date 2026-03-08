import Testing
import Foundation
@testable import PluginUpdater

@Suite("VendorResolver Tests")
struct VendorResolverTests {

    // MARK: - Priority chain

    @Test("AU component name takes highest priority")
    func audioComponentNamePriority() {
        let result = VendorResolver.resolve(
            audioComponentName: "FabFilter",
            copyright: "Copyright 2024 SomeOtherCompany",
            getInfoString: nil,
            bundleIDDomain: "fabfilter",
            parentDirectory: "VST3",
            format: .au
        )
        #expect(result == "FabFilter")
    }

    @Test("Copyright used when no AU component name")
    func copyrightFallback() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: "Copyright 2024 Xfer Records",
            getInfoString: nil,
            bundleIDDomain: "xferrecords",
            parentDirectory: "VST3",
            format: .vst3
        )
        #expect(result == "Xfer Records")
    }

    @Test("GetInfoString used when no copyright")
    func getInfoStringFallback() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: nil,
            getInfoString: "2024 Native Instruments GmbH",
            bundleIDDomain: "native-instruments",
            parentDirectory: "VST3",
            format: .vst3
        )
        #expect(result == "Native Instruments")
    }

    @Test("Bundle ID domain used when no other source")
    func bundleIDDomainFallback() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: nil,
            getInfoString: nil,
            bundleIDDomain: "eventide",
            parentDirectory: "VST3",
            format: .vst3
        )
        #expect(result == "Eventide")
    }

    @Test("Parent directory used as last resort")
    func parentDirectoryFallback() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: nil,
            getInfoString: nil,
            bundleIDDomain: nil,
            parentDirectory: "Eventide",
            format: .vst3
        )
        #expect(result == "Eventide")
    }

    @Test("Returns Unknown when all sources empty")
    func unknownFallback() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: nil,
            getInfoString: nil,
            bundleIDDomain: nil,
            parentDirectory: "VST3",
            format: .vst3
        )
        #expect(result == "Unknown")
    }

    @Test("Known plugin directories are skipped for parent directory")
    func skipsKnownPluginDirs() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: nil,
            getInfoString: nil,
            bundleIDDomain: nil,
            parentDirectory: "Components",
            format: .au
        )
        #expect(result == "Unknown")
    }

    @Test("Generic domains are skipped")
    func skipsGenericDomains() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: nil,
            getInfoString: nil,
            bundleIDDomain: "audio",
            parentDirectory: "Vendor",
            format: .vst3
        )
        #expect(result == "Vendor")
    }

    // MARK: - Copyright extraction

    @Test("Extracts vendor from standard copyright")
    func standardCopyright() {
        let result = VendorResolver.extractVendorFromCopyright("Copyright 2024 FabFilter")
        #expect(result == "FabFilter")
    }

    @Test("Extracts vendor with (c) symbol")
    func parenCCopyright() {
        let result = VendorResolver.extractVendorFromCopyright("(c) Xfer Records")
        #expect(result == "Xfer Records")
    }

    @Test("Extracts vendor with copyright symbol")
    func unicodeCopyrightSymbol() {
        let result = VendorResolver.extractVendorFromCopyright("© 2023 Valhalla DSP")
        #expect(result == "Valhalla DSP")
    }

    @Test("Strips All Rights Reserved suffix")
    func stripsAllRightsReserved() {
        let result = VendorResolver.extractVendorFromCopyright("Copyright 2024 FabFilter All Rights Reserved")
        #expect(result == "FabFilter")
    }

    @Test("Strips Inc. suffix")
    func stripsIncSuffix() {
        let result = VendorResolver.extractVendorFromCopyright("2024 Waves Inc.")
        #expect(result == "Waves")
    }

    @Test("Strips GmbH suffix")
    func stripsGmbhSuffix() {
        let result = VendorResolver.extractVendorFromCopyright("2024 Native Instruments GmbH")
        #expect(result == "Native Instruments")
    }

    @Test("Strips LLC suffix")
    func stripsLlcSuffix() {
        let result = VendorResolver.extractVendorFromCopyright("2024 Valhalla DSP, LLC")
        #expect(result == "Valhalla DSP")
    }

    @Test("Returns nil for empty string")
    func emptyStringReturnsNil() {
        let result = VendorResolver.extractVendorFromCopyright("")
        #expect(result == nil)
    }

    @Test("Handles year with comma separator")
    func yearCommaSeparator() {
        let result = VendorResolver.extractVendorFromCopyright("Copyright 2024, SomeVendor")
        #expect(result == "SomeVendor")
    }

    // MARK: - Empty/whitespace handling

    @Test("Empty AU component name falls through")
    func emptyAudioComponentName() {
        let result = VendorResolver.resolve(
            audioComponentName: "",
            copyright: "Copyright 2024 TestVendor",
            getInfoString: nil,
            bundleIDDomain: nil,
            parentDirectory: "VST3",
            format: .au
        )
        #expect(result == "TestVendor")
    }

    @Test("Whitespace-only AU component name falls through")
    func whitespaceAudioComponentName() {
        let result = VendorResolver.resolve(
            audioComponentName: "   ",
            copyright: "Copyright 2024 TestVendor",
            getInfoString: nil,
            bundleIDDomain: nil,
            parentDirectory: "VST3",
            format: .au
        )
        #expect(result == "TestVendor")
    }
}
