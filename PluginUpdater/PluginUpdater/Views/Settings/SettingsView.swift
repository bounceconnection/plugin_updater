import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @Query private var scanLocations: [ScanLocation]
    @AppStorage(Constants.UserDefaultsKeys.notificationsEnabled) private var notificationsEnabled = true
    @AppStorage(Constants.UserDefaultsKeys.manifestURL) private var manifestURL = ""
    @State private var launchAtLogin = false
    @State private var newPath = ""
    @State private var newFormat: PluginFormat = .vst3

    var body: some View {
        TabView {
            // Scan Paths
            Form {
                Section("Default Scan Locations") {
                    ForEach(scanLocations.filter(\.isDefault)) { location in
                        HStack {
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
                }

                Section("Custom Scan Locations") {
                    ForEach(scanLocations.filter { !$0.isDefault }) { location in
                        HStack {
                            PluginFormatBadge(format: location.format)
                            Text(location.path)
                                .font(.caption.monospaced())
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
                        .frame(width: 100)
                        TextField("Path", text: $newPath)
                            .font(.caption.monospaced())
                        Button("Add") {
                            guard !newPath.isEmpty else { return }
                            let location = ScanLocation(path: newPath, format: newFormat)
                            appState.modelContainer.mainContext.insert(location)
                            try? appState.modelContainer.mainContext.save()
                            newPath = ""
                        }
                    }
                }
            }
            .tabItem { Label("Scan Paths", systemImage: "folder.badge.gearshape") }

            // General
            Form {
                Section("Notifications") {
                    Toggle("Enable notifications for plugin changes", isOn: $notificationsEnabled)
                }

                Section("Update Manifest") {
                    TextField("Remote manifest URL (optional)", text: $manifestURL)
                        .font(.caption.monospaced())
                    Text("Provide a URL to a JSON manifest with latest plugin versions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Startup") {
                    Toggle("Launch at login", isOn: $launchAtLogin)
                        .onChange(of: launchAtLogin) { _, enabled in
                            do {
                                if enabled {
                                    try SMAppService.mainApp.register()
                                } else {
                                    try SMAppService.mainApp.unregister()
                                }
                            } catch {
                                launchAtLogin = !enabled
                            }
                        }
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding()
        .frame(width: 500, height: 400)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
