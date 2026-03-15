---
name: swift-conventions
description: >
  Swift language patterns, concurrency conventions, and Xcode project structure for Pluginventory.
  Use whenever writing new Swift files, adding models or services, refactoring actors, or reviewing
  code quality. Trigger on: creating new types (actors, models, extensions), choosing between
  SwiftData vs UserDefaults, structuring concurrency (actors, TaskGroup, @MainActor), file placement
  decisions, error handling patterns, adding dependencies (answer: don't), xcodegen workflow,
  NSDictionary vs Bundle for plist reading, soft-delete patterns, or any question about "where
  should I put this" or "what pattern should I use". Also trigger when the user mentions switching
  build systems, asks about third-party packages, or wants to add caching/mapping JSON files.
---

# Swift Conventions for Pluginventory

This skill encodes the Swift language patterns, naming conventions, and Xcode project
conventions used in the Pluginventory macOS app. Follow these when writing or reviewing
any Swift code in this repo.

## Language Version & Targets

- **Swift 5.9+** with strict concurrency checking
- **macOS 14.0+** minimum deployment target
- **No third-party dependencies** — use only Apple frameworks (SwiftUI, SwiftData, Foundation, AppKit, OSLog, UserNotifications)

## Project Structure

### Build System

The project uses **xcodegen** (`project.yml`) to generate the Xcode project. Never edit
`.xcodeproj` files directly. After adding or removing `.swift` files:

```bash
cd ~/pluginventory/Pluginventory && xcodegen generate
```

### File Organization

```
Pluginventory/
  App/           # @main entry point + AppState coordinator
  Models/        # SwiftData @Model types + Codable structs + enums
  Services/      # Actor-based business logic, grouped by domain
    Scanner/     # Plugin discovery and metadata extraction
    Persistence/ # SwiftData container + reconciliation
    Monitoring/  # FSEvents file watching
    Notifications/
    Updates/     # Version checking + manifest loading
  Views/         # SwiftUI views, grouped by feature
    Dashboard/
    Detail/
    Settings/
    MenuBar/
    Components/  # Small reusable view components
  Utilities/     # Constants, logging, extensions
    Extensions/  # Type extensions in separate files
  Resources/     # Assets, JSON data files
  Generated/     # Build-time generated files (AppVersion.swift)
```

Each new file goes in the appropriate subdirectory. One primary type per file, named
after the type (e.g., `PluginScanner.swift` for the `PluginScanner` actor).

## Naming Conventions

### Types
- **PascalCase** for all types: `PluginScanner`, `BundleMetadataExtractor`
- Suffix actors with their role: `PluginScanner`, `VersionChecker`, `PluginReconciler`
- Suffix SwiftData models plainly: `Plugin`, `PluginVersion`, `VendorInfo`
- Suffix views with `View`: `DashboardView`, `PluginDetailView`
- Suffix small reusable views with their UI role: `PluginFormatBadge`, `UpdateStatusIndicator`

### Properties & Methods
- **camelCase**: `bundleIdentifier`, `extractMetadata()`, `isPluginBundle`
- Boolean properties use `is`/`has`/`should` prefixes: `isRemoved`, `hasUpdate`, `isScanning`
- Computed properties read like descriptions: `architectureDisplayString`, `normalizedVersion`

### Constants
- Use an enum namespace: `Constants.defaultScanPaths`, `Constants.fsEventsDebounceSeconds`
- UserDefaults keys as static strings in `Constants`

### Section Organization
Use `// MARK: -` to separate logical sections within a file:

```swift
// MARK: - Properties
// MARK: - Initialization
// MARK: - Public Methods
// MARK: - Private Helpers
```

## Concurrency Patterns

### Actors for Background Work
All services that perform I/O or heavy computation are **actors**:

```swift
actor PluginScanner {
    func scanAllLocations(_ locations: [ScanLocation]) async throws -> [PluginMetadata] {
        try await withThrowingTaskGroup(of: [PluginMetadata].self) { group in
            // bounded concurrency via semaphore pattern
        }
    }
}
```

### @MainActor for UI State
`AppState` is `@Observable` and `@MainActor`. All UI-facing state updates happen here:

```swift
@Observable
@MainActor
final class AppState {
    var isScanning = false
    func performScan() async { ... }
}
```

### TaskGroup with Bounded Concurrency
When processing many items (e.g., scanning 1500+ plugin bundles), use a TaskGroup
with a concurrency limit to avoid resource exhaustion:

```swift
let maxConcurrency = 8
var inFlight = 0
for item in items {
    if inFlight >= maxConcurrency {
        _ = try await group.next()
        inFlight -= 1
    }
    group.addTask { try await process(item) }
    inFlight += 1
}
```

### @ModelActor for SwiftData Writes
Background SwiftData writes use `@ModelActor` to get an isolated context:

```swift
@ModelActor
actor PluginReconciler {
    func reconcile(scanned: [PluginMetadata], fullScan: Bool) throws { ... }
}
```

## Data Modeling

### SwiftData @Model
- Use `@Model` for persistent entities
- Use `@Attribute(.unique)` for natural keys (e.g., bundleIdentifier)
- Use `@Relationship` with explicit delete rules
- Prefer **soft-delete** (`isRemoved` flag) over actual deletion to preserve history

```swift
@Model
final class Plugin {
    @Attribute(.unique) var bundleIdentifier: String
    var isRemoved: Bool = false
    @Relationship(deleteRule: .cascade, inverse: \PluginVersion.plugin)
    var versions: [PluginVersion] = []
}
```

### Codable Structs for Transient Data
Data that doesn't need persistence (API responses, metadata during scanning) uses
plain `Codable` structs:

```swift
struct PluginMetadata: Sendable {
    let bundleIdentifier: String
    let version: String
    // ...
}
```

## Error Handling

- Define domain-specific error enums nested inside the type that throws them:

```swift
struct BundleMetadataExtractor {
    enum ExtractionError: Error, LocalizedError {
        case missingInfoPlist
        case missingBundleIdentifier
        // ...
    }
}
```

- Propagate errors with `throw` — avoid swallowing with `try?` unless at the UI boundary
- Log errors with `AppLogger` before presenting to the user

## Extensions

- Put type extensions in `Utilities/Extensions/` with the naming pattern `TypeName+Feature.swift`
- Example: `URL+PluginBundle.swift`, `String+Version.swift`
- Keep extensions focused on a single concern

## Logging

Use `AppLogger` (which wraps `os.Logger`) with subsystem categories:

```swift
AppLogger.log("Scan complete: \(count) plugins", category: "Scanner")
AppLogger.log("Error: \(error)", category: "Scanner", type: .error)
```

## Gotchas & Non-Obvious Patterns

These are patterns specific to this project that you wouldn't necessarily infer from
reading the code:

### Plugin Identity

The **stable identity** of a plugin is its `CFBundleIdentifier` + `PluginFormat`, not
its file path. The same plugin can exist in both `/Library/Audio/Plug-Ins/` (system)
and `~/Library/Audio/Plug-Ins/` (user). The reconciler deduplicates by keeping the
newer version. Never use file path as a primary key.

### Bundled JSON Mapping Files

When adding a new lookup service (like cask mappings or vendor URLs), follow the
**bundled JSON + optional remote override** pattern:

1. Ship a static `.json` in `Resources/` for offline use
2. Optionally fetch a remote version on update check
3. Merge remote into bundled (remote wins on conflicts)

Examples: `cask_mappings.json`, `vendor_urls.json`, `github_repos.json`

### NSDictionary for Plist Reading

When reading `Info.plist` from plugin bundles, use `NSDictionary(contentsOf:)` instead
of `Bundle(url:)`. It's significantly faster for batch operations (1500+ bundles) because
it avoids Bundle's reflection overhead. This is a deliberate performance choice.

### Debounce Pattern for FSEvents

File system events are noisy (Spotlight indexing, metadata writes). Always debounce
with a `DispatchWorkItem` (currently 3 seconds) before triggering a rescan. The debounce
cancels the previous work item if a new event arrives within the window.

### Incremental vs Full Scan

- **Full scan**: Enumerates all known directories, reconciles everything. Used on first
  launch and manual "Scan All".
- **Incremental scan**: Only re-scans the specific directories that FSEvents reported
  changes in. Runs silently (no UI progress). The `fullScan` parameter on the reconciler
  controls whether missing plugins are marked as removed.

### Two Separate Scanning States

- `isScanInProgress` (private): Actual lock preventing concurrent scans
- `isScanning` (public, UI-visible): Controls progress bar visibility
- FSEvents-triggered incremental scans set `isScanInProgress` but NOT `isScanning`,
  so the user doesn't see phantom progress bars for background rescans.

### UserDefaults for Preferences, SwiftData for Domain Data

Simple on/off preferences (notifications, launch at login, scan intervals) go in
**UserDefaults** via `@AppStorage` with keys in `Constants.UserDefaultsKeys`.
Domain objects with relationships and history (plugins, versions, vendors) go in
**SwiftData**. Don't mix these — a boolean toggle doesn't need a @Model.

### Adding New Files Checklist

After creating any new `.swift` file:
1. Place it in the correct subdirectory per the file organization above
2. Run `cd ~/pluginventory/Pluginventory && xcodegen generate`
3. If it's a test file, ensure it's under `PluginventoryTests/` mirroring the source structure

## What NOT to Do

- Don't use `ObservableObject` / `@Published` — use `@Observable` instead (macOS 14+)
- Don't use Core Data — use SwiftData
- Don't add third-party packages — find native solutions
- Don't edit `.xcodeproj` directly — modify `project.yml` and run `xcodegen generate`
- Don't use `Bundle.module` — use `Bundle.main` (we use xcodegen, not pure SPM)
- Don't use forced unwrapping (`!`) except for known-safe compile-time constants
- Don't block the main thread — use actors and async/await for all I/O
- Don't use `Bundle(url:)` for batch plist reading — use `NSDictionary(contentsOf:)`
- Don't mark plugins as removed during incremental scans — only full scans do that
