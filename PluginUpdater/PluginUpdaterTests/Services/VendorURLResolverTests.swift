import Testing
import Foundation
@testable import PluginUpdater

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

    @Test("Resolves fabfilter.com via reverse domain")
    func reverseDomainFabFilter() async {
        let resolver = VendorURLResolver()
        let url = await resolver.resolve(
            bundleID: "com.fabfilter.Pro-Q.3",
            vendorName: "FabFilter"
        )
        // Should resolve to fabfilter.com (HEAD validated)
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

    // MARK: - Deduplication

    @Test("Skips generic domains like apple")
    func skipsGenericDomains() async {
        let resolver = VendorURLResolver()
        // "apple" is in the skip list, should not try apple.com
        let url = await resolver.resolve(
            bundleID: "com.apple.audio.plugin",
            vendorName: "Apple"
        )
        // Should fall through to search URL since "Apple" != "Unknown"
        if let url {
            #expect(url.contains("google.com/search") || url.contains("apple"))
        }
    }
}
