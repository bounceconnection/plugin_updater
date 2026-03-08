import SwiftUI
import SwiftData

enum SidebarFilter: Hashable {
    case all
    case format(PluginFormat)
    case updatesAvailable
}

/// Wraps a Plugin with its computed update status so the Table can sort all columns.
struct PluginRow: Identifiable {
    let plugin: Plugin
    let availableVersion: String
    let hasUpdate: Bool
    let downloadURL: String?

    var id: PersistentIdentifier { plugin.id }
    var name: String { plugin.name }
    var vendorName: String { plugin.vendorName }
    var formatRawValue: String { plugin.format.rawValue }
    var currentVersion: String { plugin.currentVersion }
    /// 2 = update available, 1 = up to date, 0 = no data. Descending sort puts updates first.
    var updatePriority: Int { hasUpdate ? 2 : (availableVersion == "—" ? 0 : 1) }
    /// 1 = has download link, 0 = no link. For sorting.
    var hasDownload: Int { downloadURL != nil ? 1 : 0 }
}

@MainActor
struct DashboardView: View {
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<Plugin> { !$0.isRemoved }) private var plugins: [Plugin]
    @State private var sidebarSelection: SidebarFilter = .all
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\PluginRow.name)]
    @State private var selectedPluginID: PersistentIdentifier?
    @State private var showInspector = false

    private var filteredRows: [PluginRow] {
        var result = plugins

        switch sidebarSelection {
        case .all:
            break
        case .format(let format):
            result = result.filter { $0.format == format }
        case .updatesAvailable:
            result = result.filter { plugin in
                guard let entry = appState.manifestEntries[plugin.bundleIdentifier] else { return false }
                return entry.latestVersion.isNewerVersion(than: plugin.currentVersion)
            }
        }

        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.vendorName.localizedCaseInsensitiveContains(searchText)
            }
        }

        let rows = result.map { plugin -> PluginRow in
            let manifest = appState.manifestEntries
            if let entry = manifest[plugin.bundleIdentifier] {
                let hasUpdate = entry.latestVersion.isNewerVersion(than: plugin.currentVersion)
                return PluginRow(plugin: plugin, availableVersion: entry.latestVersion, hasUpdate: hasUpdate, downloadURL: entry.downloadURL)
            }
            return PluginRow(plugin: plugin, availableVersion: "—", hasUpdate: false, downloadURL: nil)
        }

        return rows.sorted(using: sortOrder)
    }

    private var updatesCount: Int {
        plugins.filter { plugin in
            guard let entry = appState.manifestEntries[plugin.bundleIdentifier] else { return false }
            return entry.latestVersion.isNewerVersion(than: plugin.currentVersion)
        }.count
    }

    private var statusSubtitle: String {
        if let error = appState.errorMessage {
            return error
        } else if let date = appState.lastScanDate {
            return "Last scan: \(date.formatted(.relative(presentation: .named)))"
        }
        return ""
    }

    private var selectedPlugin: Plugin? {
        guard let id = selectedPluginID else { return nil }
        return plugins.first { $0.id == id }
    }

    private func pluginCount(for format: PluginFormat) -> Int {
        plugins.filter { $0.format == format }.count
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebarSelection) {
                Label("All (\(plugins.count))", systemImage: "music.note.list")
                    .tag(SidebarFilter.all)
                if updatesCount > 0 {
                    Label("Updates Available (\(updatesCount))", systemImage: "arrow.up.circle.fill")
                        .tag(SidebarFilter.updatesAvailable)
                        .foregroundStyle(.green)
                }
                Section("Formats") {
                    ForEach(PluginFormat.allCases) { format in
                        Label("\(format.displayName) (\(pluginCount(for: format)))", systemImage: "puzzlepiece.extension")
                            .tag(SidebarFilter.format(format))
                    }
                }
            }
            .navigationTitle("Plugins")
            .safeAreaInset(edge: .bottom) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .opacity(0.5)
                    .padding(16)
            }
        } detail: {
            Table(filteredRows, selection: $selectedPluginID, sortOrder: $sortOrder) {
                TableColumn("Name", value: \PluginRow.name) { (row: PluginRow) in
                    Text(row.name)
                }
                TableColumn("Vendor", value: \PluginRow.vendorName) { (row: PluginRow) in
                    Text(row.vendorName)
                }
                TableColumn("Format", value: \PluginRow.formatRawValue) { (row: PluginRow) in
                    PluginFormatBadge(format: row.plugin.format)
                }
                .width(min: 50, ideal: 60, max: 80)
                TableColumn("Installed", value: \PluginRow.currentVersion) { (row: PluginRow) in
                    Text(row.currentVersion)
                        .monospacedDigit()
                }
                .width(min: 60, ideal: 80, max: 120)
                TableColumn("Available", value: \PluginRow.updatePriority) { (row: PluginRow) in
                    AvailableVersionCell(
                        availableVersion: row.availableVersion,
                        hasUpdate: row.hasUpdate
                    )
                }
                .width(min: 60, ideal: 80, max: 120)
                TableColumn("Download", value: \PluginRow.hasDownload) { (row: PluginRow) in
                    if let urlString = row.downloadURL, let url = URL(string: urlString) {
                        Link(destination: url) {
                            Label("Get", systemImage: "arrow.down.circle")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .width(min: 50, ideal: 70, max: 90)
            }
            .overlay {
                if plugins.isEmpty && !appState.isScanning {
                    ContentUnavailableView("No Plugins Found", systemImage: "puzzlepiece.extension", description: Text("Run a scan to discover your audio plugins."))
                } else if filteredRows.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    if appState.isScanning {
                        ProgressView(value: appState.scanProgress)
                            .progressViewStyle(.circular)
                            .controlSize(.regular)
                    } else {
                        Button {
                            Task { await appState.performScan() }
                        } label: {
                            HStack(spacing: 6) {
                                Text(statusSubtitle)
                                    .font(.caption)
                                Image(systemName: "arrow.clockwise")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 8) {
                        TextField("Search plugins or vendors", text: $searchText)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 180, idealWidth: 250)
                        Button {
                            showInspector.toggle()
                        } label: {
                            Label("Info", systemImage: "sidebar.trailing")
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
            .inspector(isPresented: $showInspector) {
                if let plugin = selectedPlugin {
                    PluginDetailView(plugin: plugin, manifest: appState.manifestEntries)
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                } else {
                    ContentUnavailableView("No Selection", systemImage: "cursorarrow.click", description: Text("Select a plugin to view its details."))
                        .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
                }
            }
            .onChange(of: selectedPluginID) { _, newValue in
                if newValue != nil {
                    showInspector = true
                }
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}
