import SwiftUI
import SwiftData
import ServiceManagement

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @AppStorage(Constants.UserDefaultsKeys.manifestURL) private var manifestURL = ""
    @AppStorage(Constants.UserDefaultsKeys.scanFrequency) private var scanFrequencyMinutes = Constants.Defaults.scanFrequencyMinutes
    @AppStorage(Constants.UserDefaultsKeys.checkForAppUpdates) private var checkForAppUpdates = true
    @State private var launchAtLogin = false
    @State private var didClearImageCache = false
    @State private var isCheckingForAppUpdate = false
    @State private var didCheckForAppUpdate = false

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

            // Projects
            ProjectScanSettings()
                .tabItem { Label("Projects", systemImage: "doc.text") }

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

                Section("App Updates") {
                    Toggle("Automatically check for app updates", isOn: $checkForAppUpdates)

                    HStack {
                        Text("Current version:")
                            .foregroundStyle(.secondary)
                        Text(AppVersion.displayVersion)
                            .font(.body.monospaced())
                    }

                    HStack {
                        Button(isCheckingForAppUpdate ? "Checking…" : "Check Now") {
                            isCheckingForAppUpdate = true
                            didCheckForAppUpdate = false
                            Task {
                                await appState.checkForAppUpdate()
                                isCheckingForAppUpdate = false
                                didCheckForAppUpdate = true
                            }
                        }
                        .disabled(isCheckingForAppUpdate)

                        if let update = appState.availableAppUpdate {
                            Spacer()
                            Text("v\(update.version) available")
                                .foregroundStyle(.blue)
                            Button("View Release") {
                                NSWorkspace.shared.open(update.releasePageURL)
                            }
                            .controlSize(.small)
                        } else if didCheckForAppUpdate {
                            Spacer()
                            Label("Up to date", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.subheadline)
                        }
                    }
                }
            }
            .tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding()
        .frame(width: 500, height: 450)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

private struct ProjectScanSettings: View {
    @Environment(AppState.self) private var appState
    @AppStorage(Constants.UserDefaultsKeys.scanProjectsOnLaunch)
    private var scanProjectsOnLaunch = false
    @AppStorage(Constants.UserDefaultsKeys.monitorProjectDirectories)
    private var monitorProjectDirectories = false
    @State private var projectPaths: [String] = []

    var body: some View {
        Form {
            Section("Ableton Project Folders") {
                ForEach(projectPaths, id: \.self) { path in
                    HStack {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(path)
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button(role: .destructive) {
                            projectPaths.removeAll { $0 == path }
                            saveProjectPaths()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                    }
                }

                Button("Add Folder…") {
                    chooseFolder()
                }
            }

            Section("Options") {
                Toggle("Scan projects on app launch", isOn: $scanProjectsOnLaunch)
                Toggle("Monitor project folders for changes", isOn: $monitorProjectDirectories)
                    .onChange(of: monitorProjectDirectories) { _, enabled in
                        if enabled {
                            appState.startProjectMonitoring()
                        } else {
                            appState.stopProjectMonitoring()
                        }
                    }
            }

            Section {
                Button("Scan Projects Now") {
                    Task { await appState.performProjectScan() }
                }
                .disabled(appState.isProjectScanning)
            }
        }
        .onAppear {
            projectPaths = UserDefaults.standard.stringArray(
                forKey: Constants.UserDefaultsKeys.projectScanDirectories
            ) ?? Constants.defaultProjectScanDirectories
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder containing Ableton Live projects"
        panel.prompt = "Add"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path(percentEncoded: false)
        if !projectPaths.contains(path) {
            projectPaths.append(path)
            saveProjectPaths()
        }
    }

    private func saveProjectPaths() {
        UserDefaults.standard.set(
            projectPaths,
            forKey: Constants.UserDefaultsKeys.projectScanDirectories
        )
    }
}
