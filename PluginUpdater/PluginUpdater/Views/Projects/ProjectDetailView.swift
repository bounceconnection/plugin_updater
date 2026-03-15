import SwiftUI
import SwiftData

@MainActor
struct ProjectDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let project: AbletonProject

    private var auPlugins: [AbletonProjectPlugin] {
        project.plugins.filter { $0.pluginType == "au" }
            .sorted { $0.pluginName.localizedCompare($1.pluginName) == .orderedAscending }
    }

    private var vst3Plugins: [AbletonProjectPlugin] {
        project.plugins.filter { $0.pluginType == "vst3" }
            .sorted { $0.pluginName.localizedCompare($1.pluginName) == .orderedAscending }
    }

    private var vst2Plugins: [AbletonProjectPlugin] {
        project.plugins.filter { $0.pluginType == "vst2" }
            .sorted { $0.pluginName.localizedCompare($1.pluginName) == .orderedAscending }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.name)
                        .font(.title2)
                        .fontWeight(.semibold)

                    HStack(spacing: 16) {
                        if let version = project.abletonVersion {
                            Label(version, systemImage: "music.note")
                                .font(.caption)
                        }
                        Label(
                            project.lastModified.formatted(
                                .dateTime.month(.abbreviated).day().year()
                            ),
                            systemImage: "calendar"
                        )
                        .font(.caption)
                        Label(
                            ByteCountFormatter.string(
                                fromByteCount: project.fileSize,
                                countStyle: .file
                            ),
                            systemImage: "doc"
                        )
                        .font(.caption)
                    }
                    .foregroundStyle(.secondary)

                    Text(project.filePath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                // Summary badges
                HStack(spacing: 12) {
                    StatBadge(
                        title: "Total Plugins",
                        count: project.plugins.count,
                        systemImage: "puzzlepiece.extension",
                        color: .secondary
                    )
                    StatBadge(
                        title: "Installed",
                        count: project.installedPluginCount,
                        systemImage: "checkmark.circle.fill",
                        color: .green
                    )
                    StatBadge(
                        title: "Missing",
                        count: project.missingPluginCount,
                        systemImage: "exclamationmark.triangle.fill",
                        color: project.missingPluginCount > 0 ? .red : .secondary
                    )
                }

                Divider()

                // Plugin sections
                if !auPlugins.isEmpty {
                    pluginSection(title: "AU Plugins", plugins: auPlugins)
                }
                if !vst3Plugins.isEmpty {
                    pluginSection(title: "VST3 Plugins", plugins: vst3Plugins)
                }
                if !vst2Plugins.isEmpty {
                    pluginSection(title: "VST2 Plugins", plugins: vst2Plugins)
                }

                if project.plugins.isEmpty {
                    ContentUnavailableView(
                        "No Plugins Found",
                        systemImage: "puzzlepiece.extension",
                        description: Text("This project does not use any third-party plugins.")
                    )
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("OK") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
    }

    private func pluginSection(title: String, plugins sectionPlugins: [AbletonProjectPlugin]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            ForEach(Array(sectionPlugins.enumerated()), id: \.offset) { _, plugin in
                let installed = plugin.isInstalled
                HStack {
                    Image(systemName: installed
                          ? "checkmark.circle.fill"
                          : "xmark.circle.fill")
                        .foregroundStyle(installed ? .green : .red)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(plugin.pluginName)
                            .fontWeight(.medium)
                        if let vendor = plugin.vendorName, !vendor.isEmpty {
                            Text(vendor)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Text(installed ? "Installed" : "Not Installed")
                        .font(.caption)
                        .foregroundStyle(installed ? Color.secondary : Color.red)
                }
                .padding(.vertical, 2)
            }
        }
    }
}

private struct StatBadge: View {
    let title: String
    let count: Int
    let systemImage: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(color)
            Text("\(count)")
                .font(.title3)
                .fontWeight(.semibold)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
