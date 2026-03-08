import Testing
import Foundation
@testable import PluginUpdater

@Suite("String+Version Tests")
struct VersionParserTests {

    // MARK: - normalizedVersion

    @Test("Strips lowercase v prefix")
    func stripsLowercaseV() {
        #expect("v2.1.2".normalizedVersion == "2.1.2")
    }

    @Test("Strips uppercase V prefix")
    func stripsUppercaseV() {
        #expect("V2.1.2".normalizedVersion == "2.1.2")
    }

    @Test("Strips 'Version' prefix")
    func stripsVersionPrefix() {
        #expect("Version 1.0.3".normalizedVersion == "1.0.3")
    }

    @Test("Strips 'ver' prefix")
    func stripsVerPrefix() {
        #expect("ver1.0".normalizedVersion == "1.0")
    }

    @Test("Handles version with dash separator")
    func dashSeparator() {
        #expect("v-2.0".normalizedVersion == "2.0")
    }

    @Test("Handles clean version string")
    func cleanVersion() {
        #expect("3.2.1".normalizedVersion == "3.2.1")
    }

    @Test("Trims whitespace")
    func trimsWhitespace() {
        #expect("  1.0.0  ".normalizedVersion == "1.0.0")
    }

    @Test("Handles empty string")
    func emptyString() {
        #expect("".normalizedVersion == "")
    }

    // MARK: - versionComponents

    @Test("Parses standard semver")
    func parsesSemver() {
        #expect("2.1.3".versionComponents == [2, 1, 3])
    }

    @Test("Parses two-part version")
    func parsesTwoPart() {
        #expect("1.0".versionComponents == [1, 0])
    }

    @Test("Parses single number")
    func parsesSingle() {
        #expect("5".versionComponents == [5])
    }

    @Test("Handles v prefix in components")
    func handlesVPrefixInComponents() {
        #expect("V3.0.1".versionComponents == [3, 0, 1])
    }

    @Test("Non-numeric parts are dropped")
    func nonNumericDropped() {
        #expect("1.2.beta".versionComponents == [1, 2])
    }

    @Test("Empty string returns empty array")
    func emptyComponents() {
        #expect("".versionComponents == [])
    }

    // MARK: - compareVersion

    @Test("Equal versions return orderedSame")
    func equalVersions() {
        #expect("1.0.0".compareVersion(to: "1.0.0") == .orderedSame)
    }

    @Test("Newer major version")
    func newerMajor() {
        #expect("2.0.0".compareVersion(to: "1.0.0") == .orderedDescending)
    }

    @Test("Older major version")
    func olderMajor() {
        #expect("1.0.0".compareVersion(to: "2.0.0") == .orderedAscending)
    }

    @Test("Newer minor version")
    func newerMinor() {
        #expect("1.2.0".compareVersion(to: "1.1.0") == .orderedDescending)
    }

    @Test("Newer patch version")
    func newerPatch() {
        #expect("1.0.2".compareVersion(to: "1.0.1") == .orderedDescending)
    }

    @Test("Different length versions - shorter equals longer with zeros")
    func differentLengths() {
        #expect("1.0".compareVersion(to: "1.0.0") == .orderedSame)
    }

    @Test("Different length versions - shorter is older")
    func shorterOlder() {
        #expect("1.0".compareVersion(to: "1.0.1") == .orderedAscending)
    }

    @Test("Handles V prefix in comparison")
    func vPrefixComparison() {
        #expect("V2.0".compareVersion(to: "v1.9") == .orderedDescending)
    }

    // MARK: - isNewerVersion

    @Test("isNewerVersion returns true for newer")
    func isNewerTrue() {
        #expect("2.0.0".isNewerVersion(than: "1.9.9") == true)
    }

    @Test("isNewerVersion returns false for older")
    func isNewerFalseOlder() {
        #expect("1.0.0".isNewerVersion(than: "2.0.0") == false)
    }

    @Test("isNewerVersion returns false for equal")
    func isNewerFalseEqual() {
        #expect("1.0.0".isNewerVersion(than: "1.0.0") == false)
    }

    @Test("Real-world version comparison: plugin update scenario")
    func realWorldComparison() {
        #expect("3.21".isNewerVersion(than: "3.20"))
        #expect("1.35b2".compareVersion(to: "1.35") == .orderedSame) // non-numeric suffix dropped
        #expect("V10.0.0".isNewerVersion(than: "9.9.9"))
    }

    // MARK: - csvEscaped

    @Test("Plain string is not escaped")
    func csvPlainString() {
        #expect("hello".csvEscaped == "hello")
    }

    @Test("String with comma is quoted")
    func csvComma() {
        #expect("hello, world".csvEscaped == "\"hello, world\"")
    }

    @Test("String with quotes is double-quoted")
    func csvQuotes() {
        #expect("say \"hi\"".csvEscaped == "\"say \"\"hi\"\"\"")
    }

    @Test("String with newline is quoted")
    func csvNewline() {
        #expect("line1\nline2".csvEscaped == "\"line1\nline2\"")
    }
}
