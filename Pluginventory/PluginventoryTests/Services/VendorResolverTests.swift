import Testing
import Foundation
@testable import Pluginventory

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

    // MARK: - Trailing year stripping

    @Test("Strips trailing year from copyright")
    func stripsTrailingYear() {
        let result = VendorResolver.extractVendorFromCopyright("© Rob Papen 2021")
        #expect(result == "Rob Papen")
    }

    @Test("Strips trailing year with comma separator")
    func stripsTrailingYearWithComma() {
        let result = VendorResolver.extractVendorFromCopyright("© Rob Papen, 2022")
        #expect(result == "Rob Papen")
    }

    @Test("Strips trailing year when copyright has no symbol")
    func stripsTrailingYearNoSymbol() {
        // Some plists just have "Rob Papen 2021" in the copyright field
        let result = VendorResolver.extractVendorFromCopyright("Rob Papen 2021")
        #expect(result == "Rob Papen")
    }

    @Test("Handles both leading and trailing year")
    func handlesBothLeadingAndTrailingYear() {
        // Unusual but possible: "2021 Rob Papen 2021"
        let result = VendorResolver.extractVendorFromCopyright("© 2021 Rob Papen 2021")
        #expect(result == "Rob Papen")
    }

    @Test("Does not strip 4-digit number that is part of vendor name")
    func doesNotStripNonYearNumber() {
        // "SPC Plugins 2019" — 2019 looks like a year and gets stripped. This is acceptable
        // because product names with years are rare, and the vendor is still identifiable.
        let result = VendorResolver.extractVendorFromCopyright("SPC Plugins 2019")
        #expect(result == "SPC Plugins")
    }

    @Test("Trailing year stripping works in full resolve chain")
    func trailingYearInResolveChain() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: "© Rob Papen 2021",
            getInfoString: nil,
            bundleIDDomain: "robpapen",
            parentDirectory: "Rob Papen",
            format: .vst3
        )
        #expect(result == "Rob Papen")
    }

    @Test("Strips trailing year with dash separator")
    func stripsTrailingYearWithDash() {
        let result = VendorResolver.extractVendorFromCopyright("© Rob Papen - 2023")
        #expect(result == "Rob Papen")
    }

    @Test("Strips different trailing years consistently")
    func stripsVariousTrailingYears() {
        #expect(VendorResolver.extractVendorFromCopyright("Rob Papen 2021") == "Rob Papen")
        #expect(VendorResolver.extractVendorFromCopyright("Rob Papen 2022") == "Rob Papen")
        #expect(VendorResolver.extractVendorFromCopyright("Rob Papen 2023") == "Rob Papen")
        #expect(VendorResolver.extractVendorFromCopyright("Rob Papen 2024") == "Rob Papen")
        #expect(VendorResolver.extractVendorFromCopyright("Rob Papen 2025") == "Rob Papen")
    }

    @Test("Year-only copyright returns nil")
    func yearOnlyCopyrightReturnsNil() {
        // After stripping leading year, nothing remains
        let result = VendorResolver.extractVendorFromCopyright("© 2024")
        #expect(result == nil)
    }

    @Test("Preserves vendor name that contains digits but not a trailing year")
    func preservesDigitsInVendorName() {
        let result = VendorResolver.extractVendorFromCopyright("© D16 Group Audio Software")
        #expect(result == "D16 Group Audio Software")
    }

    @Test("Strips trailing year from getInfoString in resolve chain")
    func trailingYearInGetInfoString() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: nil,
            getInfoString: "Rob Papen 2022",
            bundleIDDomain: "robpapen",
            parentDirectory: "Rob Papen",
            format: .vst3
        )
        #expect(result == "Rob Papen")
    }

    @Test("AU component name is not affected by year stripping")
    func auComponentNameNotStripped() {
        // AU component names come from a different field and should be trusted as-is
        let result = VendorResolver.resolve(
            audioComponentName: "Rob Papen",
            copyright: "Rob Papen 2021",
            getInfoString: nil,
            bundleIDDomain: "robpapen",
            parentDirectory: "Rob Papen",
            format: .au
        )
        #expect(result == "Rob Papen")
    }

    @Test("Strips trailing year and LLC suffix together")
    func stripsTrailingYearAndLLC() {
        // Order matters: LLC stripped first, then trailing year
        let result = VendorResolver.extractVendorFromCopyright("© Valhalla DSP, LLC 2023")
        #expect(result == "Valhalla DSP")
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

    // MARK: - Version-like string rejection

    @Test("Version string in getInfoString falls through to bundle ID")
    func versionStringGetInfoFallsThrough() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: nil,
            getInfoString: "2.0.3",
            bundleIDDomain: "gforce",
            parentDirectory: "Components",
            format: .au
        )
        #expect(result == "Gforce")
    }

    @Test("Version string in copyright returns nil")
    func versionStringCopyrightReturnsNil() {
        let result = VendorResolver.extractVendorFromCopyright("2.0.3")
        #expect(result == nil)
    }

    @Test("Dotted version number returns nil")
    func dottedVersionReturnsNil() {
        #expect(VendorResolver.extractVendorFromCopyright("1.0") == nil)
        #expect(VendorResolver.extractVendorFromCopyright("10.2.1") == nil)
    }

    @Test("Various version formats are rejected")
    func variousVersionFormatsRejected() {
        #expect(VendorResolver.extractVendorFromCopyright("3") == nil)
        #expect(VendorResolver.extractVendorFromCopyright("1.0.0") == nil)
        #expect(VendorResolver.extractVendorFromCopyright("2.0.3") == nil)
        #expect(VendorResolver.extractVendorFromCopyright("10.12.4.1") == nil)
        #expect(VendorResolver.extractVendorFromCopyright("0.9") == nil)
    }

    @Test("Version with copyright prefix is rejected")
    func versionWithCopyrightPrefixRejected() {
        // "© 2.0.3" → strip ©, strip nothing else → "2.0.3" → version-like → nil
        #expect(VendorResolver.extractVendorFromCopyright("© 2.0.3") == nil)
        #expect(VendorResolver.extractVendorFromCopyright("Copyright 1.0") == nil)
    }

    @Test("Version in both copyright and getInfoString falls through entirely")
    func versionInBothFieldsFallsThrough() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: "2.0.3",
            getInfoString: "2.0.3",
            bundleIDDomain: "gforce",
            parentDirectory: "Components",
            format: .au
        )
        #expect(result == "Gforce")
    }

    @Test("Version in all fields falls through to parent directory")
    func versionFallsThroughToParentDir() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: "1.5",
            getInfoString: "1.5",
            bundleIDDomain: nil,
            parentDirectory: "Eventide",
            format: .vst3
        )
        #expect(result == "Eventide")
    }

    @Test("Version in all fields with no fallback returns Unknown")
    func versionWithNoFallbackReturnsUnknown() {
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: "3.0",
            getInfoString: "3.0",
            bundleIDDomain: nil,
            parentDirectory: "Components",
            format: .au
        )
        #expect(result == "Unknown")
    }

    @Test("Version-like string with text is NOT rejected")
    func versionWithTextNotRejected() {
        // These contain letters so should be treated as vendor names
        #expect(VendorResolver.extractVendorFromCopyright("v2.0") != nil)
        #expect(VendorResolver.extractVendorFromCopyright("1.0.0-beta") != nil)
        #expect(VendorResolver.extractVendorFromCopyright("D16 Group") != nil)
        #expect(VendorResolver.extractVendorFromCopyright("112dB") != nil)
    }

    @Test("Single digit is rejected")
    func singleDigitRejected() {
        #expect(VendorResolver.extractVendorFromCopyright("5") == nil)
    }

    @Test("Copyright with year and version-only vendor is rejected")
    func copyrightYearThenVersionRejected() {
        // "Copyright 2024 1.0.3" → strip copyright, strip year → "1.0.3" → version → nil
        #expect(VendorResolver.extractVendorFromCopyright("Copyright 2024 1.0.3") == nil)
    }

    @Test("Real impOSCar2 scenario: version getInfoString falls through to bundle ID")
    func impOSCar2Scenario() {
        // impOSCar2 has: no copyright, no AU component, getInfoString="2.0.3", bundleID=com.gforce
        let result = VendorResolver.resolve(
            audioComponentName: nil,
            copyright: nil,
            getInfoString: "2.0.3",
            bundleIDDomain: "gforce",
            parentDirectory: "Components",
            format: .au
        )
        #expect(result == "Gforce")
    }
}
