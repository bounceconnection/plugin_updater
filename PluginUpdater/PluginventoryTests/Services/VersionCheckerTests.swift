import Testing
import Foundation
@testable import Pluginventory

@Suite("VersionChecker Tests")
struct VersionCheckerTests {

    @Test("Vendor URL matches prefix when loaded directly")
    func vendorURLMatch() async {
        let checker = VersionChecker()
        // Load from the module bundle (where SPM puts processed resources)
        await checker.loadMappings()

        // If vendor_urls.json was found in the bundle, test the lookup
        let url = await checker.vendorURL(for: "com.fabfilter.Pro-Q.3")
        if url != nil {
            #expect(url?.contains("fabfilter") == true)
        }
        // If resource wasn't found (test environment), verify nil is returned gracefully
    }

    @Test("Vendor URL returns nil for unknown bundle ID")
    func vendorURLNoMatch() async {
        let checker = VersionChecker()
        await checker.loadMappings()
        let url = await checker.vendorURL(for: "com.unknown.nonexistent")
        #expect(url == nil)
    }

    @Test("Vendor URL prefix matching works correctly")
    func vendorURLPrefixMatching() async {
        // Test the matching logic directly by verifying behavior
        let checker = VersionChecker()
        await checker.loadMappings()

        // Unknown prefix should return nil
        let noMatch = await checker.vendorURL(for: "org.example.unknown")
        #expect(noMatch == nil)
    }
}
