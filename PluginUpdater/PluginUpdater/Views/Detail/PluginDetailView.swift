import SwiftUI
import SwiftData
import AppKit

struct PluginDetailView: View {
    let plugin: Plugin
    let manifest: [String: UpdateManifestEntry]

    private var manifestEntry: UpdateManifestEntry? {
        manifest[plugin.bundleIdentifier]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plugin.name)
                            .font(.title2.bold())
                        Text(plugin.vendorName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    PluginFormatBadge(format: plugin.format)
                }

                Divider()

                // Info
                Group {
                    LabeledContent("Version") {
                        Text(plugin.currentVersion)
                            .monospacedDigit()
                    }
                    if let entry = manifestEntry {
                        LabeledContent("Latest") {
                            Text(entry.latestVersion)
                                .monospacedDigit()
                                .foregroundStyle(
                                    entry.latestVersion.isNewerVersion(than: plugin.currentVersion) ? .green : .secondary
                                )
                        }
                        if let url = entry.downloadURL, let downloadURL = URL(string: url) {
                            LabeledContent("Download") {
                                Link("Open", destination: downloadURL)
                            }
                        }
                    }
                    LabeledContent("Bundle ID") {
                        Text(plugin.bundleIdentifier)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                    LabeledContent("Path") {
                        HStack(spacing: 4) {
                            Text(plugin.path)
                                .font(.caption)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                            Button {
                                NSWorkspace.shared.selectFile(plugin.path, inFileViewerRootedAtPath: "")
                            } label: {
                                Image(systemName: "folder")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    LabeledContent("First Seen") {
                        Text(plugin.installedDate.formatted(.dateTime.month().day().year()))
                    }
                    LabeledContent("Last Seen") {
                        Text(plugin.lastSeenDate.formatted(.dateTime.month().day().year()))
                    }
                }

                Divider()

                VersionHistoryView(versions: plugin.versionHistory)
            }
            .padding()
        }
    }
}
