# PluginUpdater - macOS Audio Plugin Update Manager

## Context
Build a native macOS SwiftUI app that scans installed audio plugins (VST3, AU, CLAP), tracks their versions, monitors for changes, and provides a dashboard + menu bar interface for managing updates. The system has ~1500 plugins across all formats.

## Configuration
- **Organization ID**: `com.bounceconnection`
- **Bundle ID**: `com.bounceconnection.PluginUpdater`
- **App style**: Menu bar + dock (both)

## Tech Stack
- **Swift 5.9+ / SwiftUI** - Native Mac UI
- **SwiftData** - Local persistence (macOS 14+)
- **FSEvents** - File system monitoring
- **UserNotifications** - macOS notifications
- **SMAppService** - Launch at login
- **No third-party dependencies** - All native Apple frameworks

## Project Structure
```
PluginUpdater/
  PluginUpdater/
    App/
      PluginUpdaterApp.swift          # @main, MenuBarExtra + WindowGroup + Settings
      AppState.swift                  # @Observable coordinator for all services
    Models/
      PluginFormat.swift              # Enum: vst3, au, clap
      Plugin.swift                    # SwiftData model - installed plugins
      PluginVersion.swift             # SwiftData model - version history
      VendorInfo.swift                # SwiftData model - vendor metadata + URLs
      UpdateManifestEntry.swift       # Codable struct for JSON manifest
      ScanLocation.swift              # SwiftData model - configurable scan paths
    Services/
      Scanner/
        PluginScanner.swift           # Async scanner with TaskGroup parallelism
        BundleMetadataExtractor.swift # Info.plist reading (NSDictionary for speed)
        VendorResolver.swift          # Heuristic vendor extraction (AU name > copyright > bundle ID)
        VersionParser.swift           # Normalize "V2.1.2" -> "2.1.2", semver comparison
      Monitoring/
        FileSystemMonitor.swift       # FSEvents wrapper, 3s debounce for installers
      Persistence/
        PersistenceController.swift   # ModelContainer config
      Notifications/
        NotificationManager.swift     # UNUserNotificationCenter wrapper
      Updates/
        ManifestManager.swift         # Load/fetch JSON update manifest
    Views/
      Dashboard/
        DashboardView.swift           # NavigationSplitView: sidebar + list + detail
        PluginListView.swift          # Filterable/sortable plugin list
        PluginRowView.swift           # Single row in list
        FilterBarView.swift           # Format/vendor/status filters
      Detail/
        PluginDetailView.swift        # Full plugin info + version timeline
        VersionHistoryView.swift      # Version change history
      Settings/
        SettingsView.swift            # Scan paths, notifications, manifest URL
        ScanPathsEditor.swift         # Add/remove custom scan paths
      MenuBar/
        MenuBarView.swift             # Popover: summary, recent changes, scan button
      Components/
        PluginFormatBadge.swift       # Colored VST3/AU/CLAP badge
        VendorLink.swift              # Clickable vendor URL
        UpdateStatusIndicator.swift   # Update availability indicator
    Utilities/
      Constants.swift                 # Default paths, notification IDs, UserDefaults keys
      Extensions/
        URL+PluginBundle.swift
        String+Version.swift
    Resources/
      Assets.xcassets/
      default_manifest.json           # Bundled known-versions manifest
  PluginUpdaterTests/
    Services/
      PluginScannerTests.swift
      BundleMetadataExtractorTests.swift
      VersionParserTests.swift
      VendorResolverTests.swift
    Models/
      PluginModelTests.swift
    Mocks/
      MockPluginBundles/              # Fake bundles for testing
```

## Plugin Scan Directories
| Format | System Path | User Path |
|--------|-------------|-----------|
| VST3   | `/Library/Audio/Plug-Ins/VST3/` | `~/Library/Audio/Plug-Ins/VST3/` |
| AU     | `/Library/Audio/Plug-Ins/Components/` | `~/Library/Audio/Plug-Ins/Components/` |
| CLAP   | `/Library/Audio/Plug-Ins/CLAP/` | `~/Library/Audio/Plug-Ins/CLAP/` |

## Implementation Phases

### Phase 1: Xcode Project + SwiftData Models
- Create Xcode project (macOS App, SwiftUI, SwiftData, macOS 14+)
- Implement `PluginFormat`, `Plugin`, `PluginVersion`, `VendorInfo` models
- `Plugin` uses `CFBundleIdentifier` as stable identity (not file path)
- `PluginVersion` is append-only history with cascade delete from Plugin

### Phase 2: Scanner + Metadata Extraction
- `PluginScanner` as actor, uses `TaskGroup` (concurrency ~8) for 1500+ bundles
- `BundleMetadataExtractor` reads `Contents/Info.plist` via `NSDictionary(contentsOf:)`
- Handle vendor subdirectories (e.g., `VST3/Eventide/Plugin.vst3`)
- `VendorResolver` priority: AU AudioComponents name > NSHumanReadableCopyright > CFBundleGetInfoString > bundle ID domain > parent directory
- `VersionParser` strips "V" prefix, implements semver comparison

### Phase 3: Persistence + Reconciliation
- Reconciliation: match by bundleIdentifier, detect new/updated/removed plugins
- Batch SwiftData writes (single `save()` for all changes)
- Use `@ModelActor` for background persistence

### Phase 4: File System Monitoring
- FSEvents with `kFSEventStreamCreateFlagFileEvents` for recursive monitoring
- 3-second debounce (installers write multiple files)
- Trigger incremental scan of changed directory only

### Phase 5: Dashboard UI
- `NavigationSplitView` with sidebar (vendors/formats) + list + detail
- `@Query` with dynamic predicates for filtering
- Search, sort by name/vendor/format/date
- Plugin detail: name, format badge, version, path (reveal in Finder), vendor link, version history

### Phase 6: Notifications
- `UNUserNotificationCenter` for plugin updated/installed/removed events
- Request authorization on first launch

### Phase 7: Menu Bar
- `MenuBarExtra` with `.menuBarExtraStyle(.window)` for popover
- Summary stats, recent changes, "Scan Now", "Open Dashboard"

### Phase 8: Update Manifest + Settings
- Bundled JSON manifest mapping plugin IDs to latest versions + download URLs
- Optional remote manifest URL (user-configurable)
- Settings: scan paths, notification toggles, manifest URL, scan frequency, launch at login (SMAppService)

## Key Design Decisions
- **No third-party deps** - all native Apple frameworks
- **Actor-based scanner** - safe concurrency for 1500+ plugins
- **NSDictionary for plist** - faster than Bundle for batch reads
- **@Observable over ObservableObject** - better SwiftUI perf (macOS 14+)
- **Soft-delete for removed plugins** - preserves version history
- **Debounced FSEvents** - prevents scan storms during installs

## Verification
1. Build and run in Xcode
2. Verify initial scan finds ~1500 plugins across all formats
3. Install/remove a test plugin, verify FSEvents triggers rescan + notification
4. Check dashboard filtering, sorting, search work with full plugin list
5. Verify menu bar popover shows summary and recent changes
6. Run unit tests for VersionParser, VendorResolver, BundleMetadataExtractor
