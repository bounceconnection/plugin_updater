import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(Constants.UserDefaultsKeys.manifestURL) private var manifestURL = ""
    @AppStorage(Constants.UserDefaultsKeys.scanFrequency) private var scanFrequencyMinutes = Constants.Defaults.scanFrequencyMinutes
    @State private var launchAtLogin = false
    @State private var didClearImageCache = false

    private let frequencyOptions: [(label: String, minutes: Int)] = [
        ("Every 15 minutes", 15),
        ("Every 30 minutes", 30),
        ("Every hour", 60),
        ("Every 2 hours", 120),
        ("Every 6 hours", 360),
        ("Manual only", 0),
    ]

    var body: some View {
        TabView {
            // Scan Paths
            ScanPathsEditor()
                .tabItem { Label("Scan Paths", systemImage: "folder.badge.gearshape") }

            // Notifications
            NotificationSettingsView()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }

            // General
            Form {
                Section("Scanning") {
                    Picker("Auto-scan interval", selection: $scanFrequencyMinutes) {
                        ForEach(frequencyOptions, id: \.minutes) { option in
                            Text(option.label).tag(option.minutes)
                        }
                    }
                    .onChange(of: scanFrequencyMinutes) { _, newValue in
                        appState.updateAutoScanInterval(minutes: newValue)
                    }
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

                Section("Cache") {
                    HStack {
                        Button(didClearImageCache ? "Image Cache Cleared" : "Clear Image Cache") {
                            Task {
                                appState.cancelImagePrefetch()
                                await PluginImageService.shared.clearCache()
                                didClearImageCache = true
                            }
                        }
                        .disabled(didClearImageCache)
                        Spacer()
                        Text("Re-fetches plugin images on next load")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
