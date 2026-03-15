import Testing
import Foundation
@testable import Pluginventory

// MARK: - Mock URLSession

private final class MockURLSession: AppUpdateChecker.URLSessionProtocol, @unchecked Sendable {
    var data: Data = Data()
    var response: URLResponse = HTTPURLResponse(
        url: URL(string: "https://api.github.com")!,
        statusCode: 200,
        httpVersion: nil,
        headerFields: nil
    )!
    var error: Error?

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        if let error { throw error }
        return (data, response)
    }
}

// MARK: - Test Helpers

private func makeReleaseJSON(
    tagName: String = "v2.0.0",
    htmlUrl: String = "https://github.com/bounceconnection/pluginventory/releases/tag/v2.0.0",
    body: String? = "Bug fixes and improvements",
    publishedAt: String? = "2026-03-14T00:00:00Z",
    assets: [[String: String]] = []
) -> Data {
    var json: [String: Any] = [
        "tag_name": tagName,
        "html_url": htmlUrl,
        "assets": assets.map { asset in
            [
                "name": asset["name"] ?? "",
                "browser_download_url": asset["browser_download_url"] ?? "",
            ]
        },
    ]
    if let body { json["body"] = body }
    if let publishedAt { json["published_at"] = publishedAt }
    // swiftlint:disable:next force_try
    return try! JSONSerialization.data(withJSONObject: json)
}

private func makeHTTPResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
        url: URL(string: "https://api.github.com")!,
        statusCode: statusCode,
        httpVersion: nil,
        headerFields: nil
    )!
}

// MARK: - Tests

@Suite("AppUpdateChecker Tests")
struct AppUpdateCheckerTests {

    // MARK: - Positive: Update available

    @Test("Returns update when remote version is newer")
    func returnsUpdateWhenNewer() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(tagName: "v2.0.0")
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.8")

        #expect(result != nil)
        #expect(result?.version == "2.0.0")
        #expect(result?.releaseNotes == "Bug fixes and improvements")
        #expect(result?.releasePageURL.absoluteString == "https://github.com/bounceconnection/pluginventory/releases/tag/v2.0.0")
    }

    @Test("Parses .pkg download URL from assets")
    func parsesPkgAsset() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(
            tagName: "v2.0.0",
            assets: [
                [
                    "name": "Pluginventory-2.0.0.pkg",
                    "browser_download_url": "https://github.com/bounceconnection/pluginventory/releases/download/v2.0.0/Pluginventory-2.0.0.pkg",
                ],
                [
                    "name": "checksums.txt",
                    "browser_download_url": "https://github.com/bounceconnection/pluginventory/releases/download/v2.0.0/checksums.txt",
                ],
            ]
        )
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result != nil)
        #expect(result?.downloadURL?.absoluteString.hasSuffix(".pkg") == true)
    }

    @Test("Handles tag without v prefix")
    func handlesTagWithoutVPrefix() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(tagName: "2.0.0")
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result != nil)
        #expect(result?.version == "2.0.0")
    }

    @Test("Returns update for minor version bump")
    func minorVersionBump() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(tagName: "v1.1.0")
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.8")

        #expect(result != nil)
        #expect(result?.version == "1.1.0")
    }

    @Test("Returns update for patch version bump")
    func patchVersionBump() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(tagName: "v1.0.9")
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.8")

        #expect(result != nil)
        #expect(result?.version == "1.0.9")
    }

    @Test("Includes publishedAt in result")
    func includesPublishedAt() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(tagName: "v2.0.0", publishedAt: "2026-03-14T12:00:00Z")
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result?.publishedAt == "2026-03-14T12:00:00Z")
    }

    // MARK: - Negative: No update

    @Test("Returns nil when current version matches remote")
    func returnsNilWhenSameVersion() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(tagName: "v1.0.8")
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.8")

        #expect(result == nil)
    }

    @Test("Returns nil when current version is newer than remote")
    func returnsNilWhenCurrentIsNewer() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(tagName: "v1.0.0")
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.8")

        #expect(result == nil)
    }

    @Test("Returns nil when current is dev version ahead of release")
    func returnsNilForDevVersionAhead() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(tagName: "v1.0.8")
        let checker = AppUpdateChecker(session: session)

        // User on 1.1.0-dev which is ahead of latest release
        let result = await checker.checkForUpdate(currentVersion: "1.1.0")

        #expect(result == nil)
    }

    // MARK: - Negative: Error handling

    @Test("Returns nil on network error")
    func returnsNilOnNetworkError() async {
        let session = MockURLSession()
        session.error = URLError(.notConnectedToInternet)
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result == nil)
    }

    @Test("Returns nil on HTTP 404")
    func returnsNilOnNotFound() async {
        let session = MockURLSession()
        session.data = Data()
        session.response = makeHTTPResponse(statusCode: 404)
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result == nil)
    }

    @Test("Returns nil on HTTP 403 (rate limited)")
    func returnsNilOnRateLimited() async {
        let session = MockURLSession()
        session.data = Data("{\"message\":\"API rate limit exceeded\"}".utf8)
        session.response = makeHTTPResponse(statusCode: 403)
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result == nil)
    }

    @Test("Returns nil on HTTP 500")
    func returnsNilOnServerError() async {
        let session = MockURLSession()
        session.data = Data()
        session.response = makeHTTPResponse(statusCode: 500)
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result == nil)
    }

    @Test("Returns nil on malformed JSON")
    func returnsNilOnMalformedJSON() async {
        let session = MockURLSession()
        session.data = Data("not valid json".utf8)
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result == nil)
    }

    @Test("Returns nil on JSON missing required fields")
    func returnsNilOnIncompleteJSON() async {
        let session = MockURLSession()
        // Valid JSON but missing tag_name
        session.data = Data("{\"html_url\":\"https://example.com\"}".utf8)
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result == nil)
    }

    // MARK: - Edge cases

    @Test("downloadURL is nil when no .pkg asset exists")
    func noPkgAsset() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(
            tagName: "v2.0.0",
            assets: [
                ["name": "source.tar.gz", "browser_download_url": "https://example.com/source.tar.gz"],
            ]
        )
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result != nil)
        #expect(result?.downloadURL == nil)
    }

    @Test("downloadURL is nil when assets array is empty")
    func emptyAssets() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(tagName: "v2.0.0", assets: [])
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result != nil)
        #expect(result?.downloadURL == nil)
    }

    @Test("Handles nil body in release")
    func nilBody() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(tagName: "v2.0.0", body: nil)
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result != nil)
        #expect(result?.releaseNotes == nil)
    }

    @Test("Handles nil publishedAt in release")
    func nilPublishedAt() async {
        let session = MockURLSession()
        session.data = makeReleaseJSON(tagName: "v2.0.0", publishedAt: nil)
        let checker = AppUpdateChecker(session: session)

        let result = await checker.checkForUpdate(currentVersion: "1.0.0")

        #expect(result != nil)
        #expect(result?.publishedAt == nil)
    }
}
