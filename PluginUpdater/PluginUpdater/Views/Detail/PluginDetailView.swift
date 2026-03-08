import SwiftUI
import SwiftData
import AppKit

struct PluginDetailView: View {
    let plugin: Plugin
    let manifest: [String: UpdateManifestEntry]

    @State private var pluginImage: NSImage?
    @State private var imageLoaded = false

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
                        VendorLink(
                            vendorName: plugin.vendorName,
                            vendorURL: manifestEntry?.downloadURL
                        )
                        .font(.subheadline)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        PluginFormatBadge(format: plugin.format)
                        UpdateStatusIndicator(
                            installedVersion: plugin.currentVersion,
                            latestVersion: manifestEntry?.latestVersion
                        )
                    }
                }

                // Plugin image (loaded async from bundle or web)
                HStack {
                    Spacer()
                    if let pluginImage {
                        Image(nsImage: pluginImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                            .shadow(radius: 3)
                    } else if imageLoaded {
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .font(.title2)
                                .foregroundStyle(.tertiary)
                            Text("No image found")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(height: 60)
                    } else {
                        ProgressView()
                            .controlSize(.small)
                            .frame(height: 60)
                    }
                    Spacer()
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
        .task(id: plugin.id) {
            pluginImage = nil
            imageLoaded = false
            pluginImage = await PluginImageService.shared.image(
                pluginName: plugin.name,
                vendorName: plugin.vendorName,
                bundleID: plugin.bundleIdentifier,
                pluginPath: plugin.path,
                vendorURL: manifestEntry?.downloadURL
            )
            imageLoaded = true
        }
    }
}
