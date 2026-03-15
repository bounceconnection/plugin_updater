import SwiftUI
import SwiftData
import AppKit

struct ScanPathsEditor: View {
    @Environment(AppState.self) private var appState
    @Query private var scanLocations: [ScanLocation]
    @State private var newFormat: PluginFormat = .vst3

    private var defaultLocations: [ScanLocation] {
        scanLocations.filter(\.isDefault)
            .sorted { ($0.format.displayName, $0.path) < ($1.format.displayName, $1.path) }
    }

    private var customLocations: [ScanLocation] {
        scanLocations.filter { !$0.isDefault }
    }

    var body: some View {
        Form {
            Section("Default Scan Locations") {
                ForEach(defaultLocations) { location in
                    Toggle(isOn: Binding(
                        get: { location.isEnabled },
                        set: { location.isEnabled = $0 }
                    )) {
                        HStack {
                            PluginFormatBadge(format: location.format)
                            Text(location.path)
                                .font(.caption.monospaced())
                        }
                    }
                }
            }

            Section("Custom Scan Locations") {
                ForEach(customLocations) { location in
                    HStack {
                        PluginFormatBadge(format: location.format)
                        Text(location.path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            if let context = location.modelContext {
                                context.delete(location)
                                try? context.save()
                            }
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                HStack {
                    Picker("Format", selection: $newFormat) {
                        ForEach(PluginFormat.allCases) { format in
                            Text(format.displayName).tag(format)
                        }
                    }
                    .frame(width: 140)
                    Button("Add Folder…") {
                        chooseFolder()
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing \(newFormat.displayName) plugins"
        panel.prompt = "Add"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let location = ScanLocation(path: url.path(percentEncoded: false), format: newFormat)
        appState.modelContainer.mainContext.insert(location)
        try? appState.modelContainer.mainContext.save()
    }
}
