---
name: swift-testing
description: >
  Write and maintain tests for Pluginventory using Swift Testing (@Suite, @Test, #expect — NOT
  XCTest). Use whenever: writing new test files, adding test coverage for models/services/views,
  creating mock objects or test fixtures, testing actors or async code, writing regression tests
  for bug fixes, adding edge case coverage, asking about mocking strategy (protocol-based mocks,
  in-memory SwiftData containers, temp directory bundles), or discussing test organization.
  Also trigger when the user says "run the tests", "add tests for X", "write a regression test",
  "how do I mock Y", "what's the testing convention", or asks about coverage gaps. This project
  uses Swift Testing exclusively — never generate XCTest code (no XCTAssert, no XCTestCase).
---

# Swift Testing for Pluginventory

This skill covers testing conventions for the Pluginventory project using the
**Swift Testing** framework (not XCTest). Swift Testing is Apple's modern test
framework with expressive macros and better ergonomics.

## Framework Basics

### Import & Structure

```swift
import Testing
@testable import Pluginventory

@Suite("Plugin Format Tests")
struct PluginFormatTests {

    @Test("Display name returns human-readable format")
    func displayName() {
        let format = PluginFormat.vst3
        #expect(format.displayName == "VST3")
    }

    @Test("File extension matches format")
    func fileExtension() {
        #expect(PluginFormat.au.fileExtension == "component")
        #expect(PluginFormat.vst3.fileExtension == "vst3")
        #expect(PluginFormat.clap.fileExtension == "clap")
    }
}
```

### Key Macros

| Macro | Purpose |
|-------|---------|
| `@Suite("Name")` | Groups related tests with a descriptive label |
| `@Test("Description")` | Marks a test function with a human-readable description |
| `#expect(condition)` | Assert a condition is true |
| `#expect(throws: ErrorType.self) { ... }` | Assert that code throws a specific error |
| `#require(condition)` | Like #expect but stops the test on failure |

### Assertions

Prefer `#expect` for most assertions — it gives better diagnostics than XCTest's `XCTAssert`:

```swift
// Good — clear expression-based assertion
#expect(metadata.version == "3.23")
#expect(plugin.isRemoved == false)
#expect(results.count == 5)
#expect(url.isPluginBundle)

// Error testing
#expect(throws: BundleMetadataExtractor.ExtractionError.missingInfoPlist) {
    try extractor.extract(from: emptyURL)
}

// Use #require when subsequent code depends on the value
let first = try #require(results.first)
#expect(first.bundleIdentifier == "com.example.plugin")
```

## Test Organization

### Directory Structure

```
PluginventoryTests/
  Models/           # Tests for data models, enums, Codable types
  Services/         # Tests for actors, extractors, resolvers
  Views/            # Tests for view logic (not snapshot tests)
  Utilities/        # Tests for extensions and helpers
```

Mirror the source structure — `Services/PluginScanner.swift` gets tested in
`Services/PluginScannerTests.swift`.

### Naming

- Test struct: `{TypeName}Tests` (e.g., `PluginFormatTests`)
- Test methods: descriptive camelCase verbs (e.g., `stripsLowercaseVPrefix`, `auVendorFromNameField`)
- Suite description: plain English of what's being tested

### After Adding Test Files

Run `xcodegen generate` to include new test files in the Xcode project:

```bash
cd ~/plugin_updater/PluginUpdater && xcodegen generate
```

## Mocking Strategy

This project doesn't use a mocking framework. Instead, create **real but minimal
test fixtures** in-process.

### Mock Plugin Bundles

Create temporary directories with fake `Info.plist` files to test metadata extraction:

```swift
@Suite("Bundle Metadata Extraction")
struct BundleMetadataExtractorTests {

    private func createMockBundle(
        format: String = "vst3",
        plistEntries: [String: Any]
    ) throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("TestPlugin.\(format)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        let contentsDir = tmp.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsDir, withIntermediateDirectories: true)

        let plistURL = contentsDir.appendingPathComponent("Info.plist")
        let data = try PropertyListSerialization.data(
            fromPropertyList: plistEntries, format: .xml, options: 0
        )
        try data.write(to: plistURL)
        return tmp
    }

    @Test("Extracts version from CFBundleShortVersionString")
    func extractsVersion() throws {
        let bundle = try createMockBundle(plistEntries: [
            "CFBundleIdentifier": "com.test.plugin",
            "CFBundleShortVersionString": "2.1.0"
        ])
        defer { try? FileManager.default.removeItem(at: bundle) }

        let extractor = BundleMetadataExtractor()
        let metadata = try extractor.extract(from: bundle)
        #expect(metadata.version == "2.1.0")
    }
}
```

Key patterns:
- Use `UUID().uuidString` in paths to avoid test collisions
- **Always clean up** with `defer { try? FileManager.default.removeItem(at: ...) }`
- Create the minimum plist entries needed for the test

### In-Memory SwiftData

For persistence tests, use an in-memory SwiftData container:

```swift
@Suite("Reconciler Tests")
struct PluginReconcilerTests {

    private func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: Plugin.self, PluginVersion.self, VendorInfo.self, ScanLocation.self,
            configurations: config
        )
    }

    @Test("New plugins are inserted")
    func insertsNewPlugins() async throws {
        let container = try makeContainer()
        let reconciler = PluginReconciler(modelContainer: container)
        // ... test reconciliation logic
    }
}
```

### Protocol-Based Mocking (When Needed)

For services that make network calls (e.g., `VersionChecker`), extract a protocol
and provide a test implementation:

```swift
protocol VersionChecking: Sendable {
    func checkVersion(for bundleID: String) async throws -> String?
}

// In tests:
struct MockVersionChecker: VersionChecking {
    var stubResult: String?
    func checkVersion(for bundleID: String) async throws -> String? {
        stubResult
    }
}
```

## What to Test

### Always Test
- **Model properties and computed values**: enum cases, display strings, comparisons
- **Parsing logic**: version strings, plist extraction, URL detection
- **Business rules**: reconciliation (new/updated/removed), deduplication, vendor resolution
- **Error paths**: missing plist, invalid data, missing bundle identifier
- **Edge cases**: empty strings, nil values, unusual version formats ("1.0b3", "v2.1")

### Don't Test
- SwiftUI view rendering (no snapshot tests in this project)
- Trivial getters/setters
- Apple framework behavior (e.g., don't test that `FileManager.createDirectory` works)

## Running Tests

```bash
# Via xcodebuild (preferred in this environment)
cd ~/plugin_updater/PluginUpdater
xcodebuild test -project Pluginventory.xcodeproj -scheme Pluginventory -destination 'platform=macOS'

# Or use the xcodebuild MCP tool
```

The test suite currently has **71+ tests across 8+ suites**, all passing.

## Test-Driven Workflow

When implementing a new feature or fixing a bug:

1. **Write the test first** (or alongside) — describe the expected behavior
2. **Implement the feature** to make the test pass
3. **Add edge case tests** after the happy path works
4. **Run the full suite** to catch regressions

Tests aren't an afterthought — they're part of the implementation.
