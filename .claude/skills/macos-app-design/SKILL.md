---
name: macos-app-design
description: >
  macOS SwiftUI design patterns and Human Interface Guidelines for Pluginventory. Use whenever
  building new views, designing UI layouts, adding or modifying navigation (sidebar, split view,
  inspector), working with the menu bar popover, creating or editing settings tabs, adding
  toolbar buttons, designing empty states, creating detail panels, or discussing any UX decision.
  Trigger on: "design a view", "add a settings tab", "redesign the sidebar", "improve the layout",
  "add a toolbar button", "make it look better", "empty state", "confirmation dialog", "onboarding",
  "menu bar popover", "detail panel", "inspector", "keyboard shortcut", or any mention of
  typography, colors, spacing, or macOS-appropriate patterns. Do NOT trigger for: writing tests,
  generating changelogs, backend service architecture, or pure data model questions.
---

# macOS App Design for Pluginventory

This skill covers macOS-specific SwiftUI patterns and design conventions used in
Pluginventory. The app follows Apple's Human Interface Guidelines (HIG) for macOS
while using modern SwiftUI APIs.

## App Architecture

Pluginventory is a **multi-scene macOS app** with three presentation surfaces:

```swift
@main
struct PluginventoryApp: App {
    var body: some Scene {
        WindowGroup { DashboardView() }         // Main window
        Settings { SettingsView() }              // Preferences (⌘,)
        MenuBarExtra("Pluginventory", ...) {     // Menu bar icon
            MenuBarPopoverView()
        }
        .menuBarExtraStyle(.window)
    }
}
```

### When to Use Each Scene Type
- **WindowGroup**: Main content windows. Pluginventory has one: the dashboard.
- **Settings**: macOS preferences window. Opens via ⌘, or app menu. Use `TabView` inside.
- **MenuBarExtra**: Persistent menu bar presence. Use `.window` style for rich content, `.menu` for simple lists.

## Navigation Pattern: NavigationSplitView

The main dashboard uses a **3-column split view** (sidebar + content list + detail):

```swift
NavigationSplitView {
    // Sidebar: format filters, counts
    List(selection: $selectedFormat) {
        ForEach(formats) { format in
            Label(format.displayName, systemImage: format.icon)
                .badge(countFor(format))
        }
    }
} content: {
    // Content: plugin list with search and sorting
    Table(filteredPlugins, selection: $selectedPlugin) {
        TableColumn("Name", value: \.name)
        TableColumn("Version", value: \.version)
        // ...
    }
    .searchable(text: $searchText)
} detail: {
    // Detail: plugin inspector
    if let plugin = selectedPlugin {
        PluginDetailView(plugin: plugin)
    } else {
        ContentUnavailableView("Select a Plugin", systemImage: "puzzlepiece")
    }
}
```

This is the standard macOS pattern for list-detail apps (like Finder, Mail, Music).
Prefer `NavigationSplitView` over `NavigationStack` for macOS apps with browsable content.

## State Management

### @Observable AppState

A single `@Observable` coordinator manages all app-level state:

```swift
@Observable
@MainActor
final class AppState {
    var isScanning = false
    var scanProgress: Double = 0
    // ...
}
```

Distribute via `.environment()` at the app root. Views access it with `@Environment`.

### @Query for SwiftData

Views that display persisted data use `@Query` with predicates and sort descriptors:

```swift
@Query(filter: #Predicate<Plugin> { !$0.isRemoved }, sort: \.name)
private var plugins: [Plugin]
```

This auto-refreshes when SwiftData changes — no manual observation needed.

### Local @State

UI-only state (search text, selection, sheet presentation) stays local:

```swift
@State private var searchText = ""
@State private var selectedPlugin: Plugin?
@State private var showingDeleteConfirmation = false
```

### Rule of Thumb
- **App-wide, persisted, or shared** → AppState or SwiftData @Query
- **View-local, ephemeral** → @State
- **Passed down to child views** → Direct property or @Binding

## Component Design

### Small Reusable Components

Extract repeated UI patterns into standalone `View` structs:

```swift
struct PluginFormatBadge: View {
    let format: PluginFormat

    var body: some View {
        Text(format.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(format.color.opacity(0.15))
            .foregroundStyle(format.color)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
```

### Inspector/Detail Pattern

Use `LabeledContent` for consistent key-value layouts in detail panels:

```swift
LabeledContent("Bundle ID") { Text(plugin.bundleIdentifier) }
LabeledContent("Format") { PluginFormatBadge(format: plugin.format) }
LabeledContent("Version") { Text(plugin.version ?? "Unknown") }
LabeledContent("Location") {
    Button("Reveal in Finder") { NSWorkspace.shared.selectFile(...) }
}
```

### Empty States

Always handle empty content with `ContentUnavailableView`:

```swift
if plugins.isEmpty {
    ContentUnavailableView(
        "No Plugins Found",
        systemImage: "puzzlepiece",
        description: Text("Run a scan to discover installed plugins.")
    )
} else {
    // ... list content
}
```

## Settings Design

Use a `TabView` with `.tabItem` labels for the preferences window:

```swift
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gear") }
            ScanPathsEditor()
                .tabItem { Label("Scan Paths", systemImage: "folder") }
        }
        .frame(width: 500)
    }
}
```

- Keep the settings window a fixed, reasonable width (~450-550pt)
- Use `Form` inside each tab for consistent spacing
- Group related settings with `Section` headers
- Use `Toggle`, `Picker`, and `TextField` — standard macOS controls

## Menu Bar (MenuBarExtra)

The menu bar popover provides a quick summary without opening the main window:

```swift
MenuBarExtra("Pluginventory", systemImage: "puzzlepiece.extension") {
    MenuBarPopoverView()
}
.menuBarExtraStyle(.window)  // Rich content popover, not just a menu
```

Design guidelines:
- Keep it **lightweight** — summary stats, quick actions, recent changes
- Provide a "Open Dashboard" button to jump to the full window
- Don't duplicate full dashboard functionality in the popover

## macOS-Specific Patterns

### Toolbar

```swift
.toolbar {
    ToolbarItem(placement: .primaryAction) {
        Button("Scan", systemImage: "arrow.clockwise") { ... }
    }
    ToolbarItem(placement: .automatic) {
        // Secondary actions
    }
}
```

### Context Menus

```swift
.contextMenu {
    Button("Reveal in Finder") { ... }
    Button("Copy Bundle ID") { ... }
    Divider()
    Button("Hide Plugin") { ... }
}
```

### Keyboard Shortcuts

Add keyboard shortcuts for frequent actions:

```swift
Button("Scan All") { ... }
    .keyboardShortcut("r", modifiers: .command)
```

### System Integration
- **NSWorkspace**: Reveal files in Finder, open URLs
- **SMAppService**: Launch at login
- **UNUserNotificationCenter**: Native notifications for plugin changes
- **NSPasteboard**: Copy to clipboard

## Typography & Spacing

Follow macOS conventions:
- **Title**: `.title2` or `.title3` for section headers (not `.largeTitle` — that's iOS)
- **Body**: Default system font for content
- **Caption**: `.caption` or `.caption2` for metadata, badges
- **Monospaced**: `.monospaced()` for version numbers, bundle IDs, file paths
- **Spacing**: Use system defaults — don't override padding unless necessary

## Color & Styling

- Use **semantic colors** (`.primary`, `.secondary`, `.accentColor`) not hard-coded colors
- Use `.opacity()` for subtle backgrounds (e.g., badge backgrounds at 0.15)
- Respect the user's accent color and dark/light mode — never force a color scheme
- Use SF Symbols for icons — they scale with Dynamic Type and match the system style

## What NOT to Do

- Don't use `.largeTitle` — it looks out of place on macOS
- Don't use full-screen sheets — use `.sheet()` sparingly; prefer inline detail panels
- Don't use bottom tabs (that's iOS) — use sidebar navigation or toolbar
- Don't force window sizes — let the user resize, but set reasonable minimum sizes
- Don't create custom title bars — use the standard window chrome
- Don't put critical actions only in context menus — always have a primary UI path
