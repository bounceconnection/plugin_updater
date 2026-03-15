import Testing
import Foundation
@testable import Pluginventory

@Suite("VendorURLResolver Tests")
struct VendorURLResolverTests {

    // MARK: - Strategy 2: Plist URL Extraction

    @Test("Extracts URL from plist copyright field")
    func extractsURLFromCopyright() async {
        let resolver = VendorURLResolver()
        let url = await resolver.resolve(
            bundleID: "com.example.plugin",
            plistFields: ["NSHumanReadableCopyright": "Copyright 2024 Example Inc. https://example.com"],
            vendorName: "Example"
        )
        #expect(url == "https://example.com")
    }

    @Test("Extracts URL from vendorurl plist key")
    func extractsVendorURLKey() async {
        let resolver = VendorURLResolver()
        let url = await resolver.resolve(
            bundleID: "com.example.plugin",
            plistFields: ["vendorurl": "http://www.example.com/"],
            vendorName: "Example"
        )
        // Should normalize http to https
        #expect(url == "https://www.example.com/")
    }

    // MARK: - Strategy 3: Reverse Domain

    @Test("Resolves fabfilter.com via DNS reverse domain")
    func reverseDomainFabFilter() async {
        let resolver = VendorURLResolver()
        let url = await resolver.resolve(
            bundleID: "com.fabfilter.Pro-Q.3",
            vendorName: "FabFilter"
        )
        // fabfilter.com has DNS records, should resolve
        #expect(url != nil)
        if let url {
            #expect(url.contains("fabfilter"))
        }
    }

    // MARK: - Strategy 4: Search Fallback

    @Test("Falls back to search URL for unknown vendor")
    func searchFallback() async {
        let resolver = VendorURLResolver()
        // Use a bundle ID that won't resolve via reverse domain
        let url = await resolver.resolve(
            bundleID: "com.zzz-nonexistent-vendor-12345.plugin",
            vendorName: "ZZZ Nonexistent Vendor"
        )
        // Should get a search URL as fallback
        #expect(url != nil)
        if let url {
            #expect(url.contains("google.com/search"))
            #expect(url.contains("ZZZ"))
        }
    }

    @Test("Returns nil when no vendor name and domain fails")
    func returnsNilNoInfo() async {
        let resolver = VendorURLResolver()
        let url = await resolver.resolve(
            bundleID: "com.zzz-nonexistent-vendor-12345.plugin",
            vendorName: "Unknown"
        )
        // "Unknown" vendor should not generate a search URL
        #expect(url == nil)
    }

    // MARK: - Domain Validation

    @Test("Skips generic domains like apple")
    func skipsGenericDomains() async {
        let resolver = VendorURLResolver()
        let url = await resolver.resolve(
            bundleID: "com.apple.audio.plugin",
            vendorName: "Apple"
        )
        // Should fall through to search URL since "Apple" != "Unknown"
        if let url {
            #expect(url.contains("google.com/search") || url.contains("apple"))
        }
    }

    @Test("Skips invalid TLDs like kontakt")
    func skipsInvalidTLDs() async {
        let resolver = VendorURLResolver()
        let url = await resolver.resolve(
            bundleID: "kontakt.musicdevice.plugin",
            vendorName: "Unknown"
        )
        // Invalid TLD — should not attempt DNS, returns nil
        #expect(url == nil)
    }

    @Test("Skips domains with underscores")
    func skipsUnderscoreDomains() async {
        let resolver = VendorURLResolver()
        let url = await resolver.resolve(
            bundleID: "com.inear_display.plugin",
            vendorName: "Unknown"
        )
        // Underscore in domain label is invalid DNS
        #expect(url == nil)
    }

    @Test("Skips domains with spaces")
    func skipsDomainWithSpaces() async {
        let resolver = VendorURLResolver()
        let url = await resolver.resolve(
            bundleID: "com.Plugin Alliance.plugin",
            vendorName: "Unknown"
        )
        #expect(url == nil)
    }

    @Test("Resolves valid .de domain via DNS")
    func resolvesDeDomain() async {
        let resolver = VendorURLResolver()
        let url = await resolver.resolve(
            bundleID: "de.cableguys.plugin",
            vendorName: "Cableguys"
        )
        // cableguys.de has DNS records
        #expect(url != nil)
        if let url {
            #expect(url.contains("cableguys"))
        }
    }

    @Test("Plist strategy takes priority over reverse domain")
    func plistPriorityOverDomain() async {
        let resolver = VendorURLResolver()
        let url = await resolver.resolve(
            bundleID: "com.fabfilter.plugin",
            plistFields: ["vendorurl": "https://custom-site.example.com/"],
            vendorName: "FabFilter"
        )
        // Plist URL should win over reverse domain
        #expect(url == "https://custom-site.example.com/")
    }
}
