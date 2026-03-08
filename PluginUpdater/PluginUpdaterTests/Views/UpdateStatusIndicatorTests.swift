import Testing
@testable import PluginUpdater

@Suite("UpdateStatusIndicator Tests")
struct UpdateStatusIndicatorTests {

    @Test("Update available when latest is newer")
    func updateAvailable() {
        let indicator = UpdateStatusIndicator(installedVersion: "1.0.0", latestVersion: "2.0.0")
        #expect(indicator.status == .updateAvailable)
    }

    @Test("Up to date when versions match")
    func upToDate() {
        let indicator = UpdateStatusIndicator(installedVersion: "1.0.0", latestVersion: "1.0.0")
        #expect(indicator.status == .upToDate)
    }

    @Test("Up to date when installed is newer")
    func installedNewer() {
        let indicator = UpdateStatusIndicator(installedVersion: "2.0.0", latestVersion: "1.0.0")
        #expect(indicator.status == .upToDate)
    }

    @Test("Unknown when no latest version")
    func unknownNoLatest() {
        let indicator = UpdateStatusIndicator(installedVersion: "1.0.0", latestVersion: nil)
        #expect(indicator.status == .unknown)
    }
}
