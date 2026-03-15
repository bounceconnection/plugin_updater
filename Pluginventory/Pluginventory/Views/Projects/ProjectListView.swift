import SwiftUI
import SwiftData
import AppKit

/// Sortable row wrapper for AbletonProject, matching the PluginRow pattern used in DashboardView.
struct ProjectRow: Identifiable {
    let project: AbletonProject
    var id: PersistentIdentifier { project.id }
    var name: String { project.name }
    var abletonVersion: String { project.abletonVersion ?? "" }
    var pluginCount: Int { project.plugins.count }
    var missingCount: Int { project.missingPluginCount }
    var lastModified: Date { project.lastModified }
    var fileSize: Int64 { project.fileSize }
    var filePath: String { project.filePath }
}

@MainActor
struct ProjectListView: View {
    let projects: [AbletonProject]
    let searchText: String
    let onSelectProject: (AbletonProject) -> Void

    @State private var sortOrder: [KeyPathComparator<ProjectRow>] = restoredProjectSortOrder()
    @State private var selectedProjectIDs: Set<PersistentIdentifier> = []

    private static let projectColumnMap: [String: PartialKeyPath<ProjectRow>] = [
        "name": \ProjectRow.name,
        "abletonVersion": \ProjectRow.abletonVersion,
        "pluginCount": \ProjectRow.pluginCount,
        "missingCount": \ProjectRow.missingCount,
        "lastModified": \ProjectRow.lastModified,
        "fileSize": \ProjectRow.fileSize,
        "filePath": \ProjectRow.filePath,
    ]

    private static func restoredProjectSortOrder() -> [KeyPathComparator<ProjectRow>] {
        let defaults = UserDefaults.standard
        guard let column = defaults.string(forKey: Constants.UserDefaultsKeys.projectSortColumn) else {
            return [KeyPathComparator(\ProjectRow.name)]
        }
        let ascending = defaults.object(forKey: Constants.UserDefaultsKeys.projectSortAscending) as? Bool ?? true
        let order: SortOrder = ascending ? .forward : .reverse
        switch column {
        case "name": return [KeyPathComparator(\ProjectRow.name, order: order)]
        case "abletonVersion": return [KeyPathComparator(\ProjectRow.abletonVersion, order: order)]
        case "pluginCount": return [KeyPathComparator(\ProjectRow.pluginCount, order: order)]
        case "missingCount": return [KeyPathComparator(\ProjectRow.missingCount, order: order)]
        case "lastModified": return [KeyPathComparator(\ProjectRow.lastModified, order: order)]
        case "fileSize": return [KeyPathComparator(\ProjectRow.fileSize, order: order)]
        case "filePath": return [KeyPathComparator(\ProjectRow.filePath, order: order)]
        default: return [KeyPathComparator(\ProjectRow.name)]
        }
    }

    private func saveProjectSortOrder() {
        guard let first = sortOrder.first else { return }
        let columnName = Self.projectColumnMap.first { $0.value == first.keyPath }?.key ?? "name"
        UserDefaults.standard.set(columnName, forKey: Constants.UserDefaultsKeys.projectSortColumn)
        UserDefaults.standard.set(first.order == .forward, forKey: Constants.UserDefaultsKeys.projectSortAscending)
    }

    private var filteredRows: [ProjectRow] {
        var result = projects
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText)
            }
        }
        let rows = result.map { ProjectRow(project: $0) }
        return rows.sorted(using: sortOrder)
    }

    var body: some View {
        let rows = filteredRows

        VStack(spacing: 0) {
            Table(rows, selection: $selectedProjectIDs, sortOrder: $sortOrder) {
                TableColumn("Name", value: \ProjectRow.name) { row in
                    Text(row.name)
                        .fontWeight(.medium)
                }
                TableColumn("Ableton Version", value: \ProjectRow.abletonVersion) { row in
                    Text(row.abletonVersion)
                        .foregroundStyle(.secondary)
                }
                .width(ideal: 120)
                TableColumn("Plugins", value: \ProjectRow.pluginCount) { row in
                    Label("\(row.pluginCount)", systemImage: "puzzlepiece.extension")
                        .monospacedDigit()
                }
                .width(ideal: 65)
                TableColumn("Missing", value: \ProjectRow.missingCount) { row in
                    if row.missingCount > 0 {
                        Label("\(row.missingCount)", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .monospacedDigit()
                    } else {
                        Text("0")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                .width(ideal: 65)
                TableColumn("Last Modified", value: \ProjectRow.lastModified) { row in
                    Text(row.lastModified.formatted(
                        .dateTime.month(.abbreviated).day().year()
                    ))
                }
                .width(ideal: 110)
                TableColumn("Size", value: \ProjectRow.fileSize) { row in
                    Text(ByteCountFormatter.string(
                        fromByteCount: row.fileSize,
                        countStyle: .file
                    ))
                    .monospacedDigit()
                }
                .width(ideal: 70)
                TableColumn("Path", value: \ProjectRow.filePath) { row in
                    Text(row.filePath)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                        .help(row.filePath)
                }
                .width(ideal: 200)
            }
            .contextMenu(forSelectionType: PersistentIdentifier.self) { ids in
                if !ids.isEmpty {
                    Button("Reveal in Finder") {
                        revealInFinder(ids: ids)
                    }
                    Button("Copy Path\(ids.count > 1 ? "s" : "")") {
                        copyPaths(ids: ids)
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first,
                   let project = projects.first(where: { $0.id == id }) {
                    onSelectProject(project)
                }
            }
            .overlay {
                if rows.isEmpty && !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if projects.isEmpty {
                    ContentUnavailableView(
                        "No Projects Scanned",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text(
                            "Configure Ableton project folders in Settings and scan to see plugin usage."
                        )
                    )
                }
            }
            .onChange(of: sortOrder) { _, _ in
                saveProjectSortOrder()
            }

            HStack {
                Text("\(rows.count) project\(rows.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)
        }
    }

    // MARK: - Actions

    private func revealInFinder(ids: Set<PersistentIdentifier>) {
        let urls = projects
            .filter { ids.contains($0.id) }
            .map { URL(fileURLWithPath: $0.filePath) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func copyPaths(ids: Set<PersistentIdentifier>) {
        let paths = projects
            .filter { ids.contains($0.id) }
            .map(\.filePath)
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths, forType: .string)
    }
}
