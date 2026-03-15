import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pluginventory")
                .font(.headline)
            Divider()

            // App update banner
            if let update = appState.availableAppUpdate {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Update Available: v\(update.version)")
                        .font(.subheadline.bold())
                    Spacer()
                    Button("View Release") {
                        NSWorkspace.shared.open(update.releasePageURL)
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                Divider()
            }

            // Stats
            HStack {
                Label("\(appState.totalPluginCount) plugins", systemImage: "puzzlepiece.extension")
                    .font(.subheadline)
                Spacer()
                if appState.updatesAvailableCount > 0 {
                    Text("\(appState.updatesAvailableCount) updates")
                        .font(.subheadline.bold())
                        .foregroundStyle(.green)
                }
            }

            if let date = appState.lastScanDate {
                Text("Last scan: \(date.formatted(.relative(presentation: .named)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("No scan performed yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if appState.isScanning {
                ProgressView(value: appState.scanProgress)
                    .controlSize(.small)
            }

            // Recent changes
            if !appState.recentChanges.isEmpty {
                Divider()
                Text("Recent Changes")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ForEach(appState.recentChanges.prefix(5), id: \.self) { change in
                    Text(change)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Divider()

            // Actions
            Button {
                Task { await appState.performScan() }
            } label: {
                Label(appState.isScanning ? "Scanning…" : "Scan & Check for Updates", systemImage: "arrow.clockwise")
            }
            .disabled(appState.isScanning)

            Button {
                NSApp.activate()
                if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            } label: {
                Label("Open Dashboard", systemImage: "macwindow")
            }

            Button("Open Logs Folder") {
                let url = AppLogger.shared.logsDirectoryURL
                NSWorkspace.shared.open(
                    url,
                    configuration: NSWorkspace.OpenConfiguration()
                ) { _, _ in }
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Pluginventory", systemImage: "power")
            }
        }
        .padding()
        .frame(width: 260)
    }
}
