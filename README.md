# Plugin Updater

a macOS app that scans all your installed audio plugins (AU, CLAP, VST2, VST3), tracks their versions, and automatically checks for available updates.

![Dashboard](screenshots/dashboard.png)

## Features

- **Automatic Plugin Discovery** — Scans standard macOS audio plugin directories and reads bundle metadata (CFBundleIdentifier, version, vendor)
- **Update Detection** — Find newer versions of your installed plugins upon each scan
- **Format Support** — AU, CLAP, VST2, and VST3 plugin formats
- **Multi-Select & Bulk Actions** — Cmd+click or Shift+click to select multiple plugins, then right-click for bulk operations
- **Context Menu** — Copy Paths, Copy Full Details, Reveal in Finder, Open Publisher Website, and Hide/Unhide actions on any selection
- **CPU Architecture Detection** — Reads Mach-O headers to show Apple Silicon, Intel 64, Universal, or legacy (Intel 32/PowerPC) status with warning badges for legacy plugins
- **File Size & Date Added** — Shows bundle size and filesystem creation date for each plugin
- **Sortable Columns** — Sort by name, vendor, format, installed version, available version, architecture, size, or date added
- **Status Bar** — Shows total plugin count and current selection count at the bottom of the table
- **Smart Vendor Resolution** — Automatically normalizes inconsistent vendor names across formats (e.g., "Plugin-alliance" → "Plugin Alliance") and strips trailing copyright years (e.g., "Rob Papen 2021" → "Rob Papen")
- **Hide Plugins** — Right-click to hide plugins you don't care about; view and unhide them from the Hidden section in the sidebar
- **Sidebar Filtering** — Filter by format (AU, CLAP, VST2, VST3) or show only plugins with updates available
- **Detail Inspector** — View architecture, size, bundle ID, file path, version history, and download links for any plugin
- **Real-time Monitoring** — Uses FSEvents to detect plugin changes in the background and trigger incremental scans
- **Menu Bar Access** — Quick status view from the menu bar showing recent changes and update counts
- **Notifications** — Get notified when plugins are added, removed, or updated

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 16.0+ (to build from source)

## Installation

### Download the Installer (easiest)

Download the latest **`.pkg` installer** from the [Releases page](https://github.com/bounceconnection/plugin_updater/releases):

1. Download `PluginUpdater-<version>.pkg`.
2. Double-click the file to launch the macOS Installer.
3. Follow the prompts — the app is installed to `/Applications`.

> **Gatekeeper note:** Builds from GitHub Actions are unsigned. If macOS blocks the installer, right-click the `.pkg` → **Open** → **Open** to proceed.

### Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/bounceconnection/plugin_updater.git
   cd plugin_updater/PluginUpdater
   ```

2. Generate the Xcode project (requires [xcodegen](https://github.com/yonaskolb/XcodeGen)):
   ```bash
   brew install xcodegen
   xcodegen generate
   ```

3. Open and build:
   ```bash
   open PluginUpdater.xcodeproj
   ```
   Then press **Cmd+R** to build and run.

### Build the .pkg Installer Locally

```bash
# Requires Xcode command-line tools and xcodegen
brew install xcodegen
./scripts/build-installer.sh
# Output: build/PluginUpdater-1.0.0.pkg
```

### Alternative: Swift Package Manager

```bash
cd PluginUpdater
swift build
```

## Usage

1. **Launch the app** — On first run, it automatically scans the default plugin directories:
   - `/Library/Audio/Plug-Ins/Components/` (Audio Units)
   - `/Library/Audio/Plug-Ins/CLAP/` (CLAP)
   - `/Library/Audio/Plug-Ins/VST/` (VST2)
   - `/Library/Audio/Plug-Ins/VST3/` (VST3)

2. **Scan for plugins** — Click the **Scan Now** button in the toolbar to rescan all directories.

3. **Check for updates** — After scanning, the app automatically queries the Homebrew Formulae API for newer versions. Plugins with available updates show a green version number in the **Available** column.

4. **Filter and sort** — Use the sidebar to filter by format or show only plugins with updates. Click any column header to sort.

5. **View details** — Select a plugin and click **Info** to open the detail inspector showing bundle ID, file path, version history, and download links.

6. **Add scan locations** — Go to **Settings** (Cmd+,) to add custom plugin directories.

## How Update Checking Works

Plugin Updater uses a mapping of plugin bundle ID prefixes to [Homebrew Cask](https://formulae.brew.sh/) names. When you scan, it:

1. Reads each plugin's `CFBundleIdentifier` and `CFBundleShortVersionString` from its `Info.plist`
2. Matches bundle IDs against known cask mappings (e.g., `com.fabfilter.Pro-Q` -> `fabfilter-pro-q`)
3. Queries `https://formulae.brew.sh/api/cask/<name>.json` for the latest version
4. Compares installed vs. latest and highlights available updates

The cask mappings file (`Resources/cask_mappings.json`) can be extended to support additional vendors.

## Architecture

```
PluginUpdater/
  App/
    PluginUpdaterApp.swift    # App entry point, window/menu bar setup
    AppState.swift            # Observable state, scan orchestration
  Models/                     # SwiftData models (Plugin, PluginVersion, ScanLocation, etc.)
                              # CPUArchitecture enum and display helpers
  Services/
    Scanner/                  # Plugin discovery, metadata extraction, Mach-O architecture detection
    Monitoring/               # FSEvents file system monitoring
    Persistence/              # SwiftData reconciliation with vendor name normalization
    Notifications/            # macOS notification delivery
    Updates/                  # Homebrew API version checking, manifest management
  Views/
    Dashboard/                # Main table view with multi-select, context menu, status bar
    Detail/                   # Plugin detail inspector with architecture and size
    Settings/                 # Scan paths editor, preferences
    MenuBar/                  # Menu bar popover
    Components/               # Reusable UI components (format badge, vendor link, etc.)
  Utilities/                  # Constants, URL/String extensions
  Resources/                  # Cask mappings, default manifest, assets
```

**Key design decisions:**
- **SwiftData** for persistence — plugins, versions, and scan locations stored locally
- **Actor-based concurrency** — scanner, reconciler, and version checker use Swift actors for thread safety
- **No third-party dependencies** — pure Swift/SwiftUI, ships as a single app bundle
- **Plugin identity keyed on CFBundleIdentifier** — not file path, so moved plugins are tracked correctly

## Development Workflow

### Branching

- **`main`** — stable releases only. Never push directly.
- **`dev`** — integration branch. All feature/fix PRs target `dev`.
- Feature branches: `git checkout dev && git checkout -b feature/<description>`

### CI

CI runs automatically on:
- All PRs targeting `dev` or `main`
- All pushes to `dev`

### Releasing

Releases are triggered via the **Promote to Main** workflow in GitHub Actions:

1. Go to **Actions → Promote to Main → Run workflow**
2. Choose a version (or leave blank for auto-bump):
   - **Blank** — auto-increments the patch version (e.g. `1.2.3` → `1.2.4`)
   - **`X.Y.Z`** — uses the exact version you specify (e.g. `2.0.0` for a major release)
3. The workflow:
   1. Creates a PR from `dev` → `main` (or reuses an existing one)
   2. Merges the PR into `main`
   3. Tags the merge commit as `vX.Y.Z`
   4. The tag triggers the **Release** workflow, which builds the `.pkg` installer and creates a GitHub Release

### Version Numbering

Follow [Semantic Versioning](https://semver.org/):
- **Patch** (`1.2.3` → `1.2.4`) — bug fixes, minor improvements (default)
- **Minor** (`1.2.4` → `1.3.0`) — new features, backward-compatible
- **Major** (`1.3.0` → `2.0.0`) — breaking changes

## Troubleshooting

### Debug Logging

By default, project scans produce minimal log output. To enable verbose per-plugin matching logs for troubleshooting:

```bash
defaults write com.tomioueda.PluginUpdater debugVerboseLogging -bool YES
```

Then re-run the scan. Logs are written to `~/Library/Logs/PluginUpdater/` (daily rolling files, kept for 7 days).

To disable verbose logging:

```bash
defaults delete com.tomioueda.PluginUpdater debugVerboseLogging
```

## License

This project is licensed under the [GNU General Public License v3.0](LICENSE).
