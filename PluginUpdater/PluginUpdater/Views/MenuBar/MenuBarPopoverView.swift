import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plugin Updater")
                .font(.headline)
            Divider()
            Text("\(appState.totalPluginCount) plugins")
                .font(.subheadline)
            if appState.updatesAvailableCount > 0 {
                Text("\(appState.updatesAvailableCount) updates available")
                    .font(.subheadline)
                    .foregroundStyle(.green)
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
            if !appState.recentChanges.isEmpty {
                Divider()
                ForEach(appState.recentChanges.prefix(5), id: \.self) { change in
                    Text(change)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            Button(appState.isScanning ? "Scanning..." : "Scan Now") {
                Task { await appState.performScan() }
            }
            .disabled(appState.isScanning)
            Button("Open Dashboard") {
                NSApp.activate()
                if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        .padding()
        .frame(width: 250)
    }
}
