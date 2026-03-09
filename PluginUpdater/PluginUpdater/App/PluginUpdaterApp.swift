import SwiftUI
import SwiftData
import AppKit

@main
struct PluginUpdaterApp: App {
    let modelContainer: ModelContainer
    @State private var appState: AppState

    init() {
        do {
            let container = try PersistenceController.makeContainer()
            self.modelContainer = container
            self._appState = State(initialValue: AppState(modelContainer: container))
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environment(appState)
                .task {
                    await initialSetup()
                }
        }
        .modelContainer(modelContainer)

        MenuBarExtra("Plugin Updater", image: Constants.AssetNames.menuBarIcon) {
            MenuBarPopoverView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Scan & Check for Updates") {
                    Task { await appState.performScan() }
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(appState.isScanning)

                Divider()

                Button("Export Plugin List…") {
                    exportCSV()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }
    }

    @MainActor
    private func exportCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "plugins.csv"
        panel.prompt = "Export"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        let csv = appState.exportPluginListCSV()
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    @MainActor
    private func initialSetup() async {
        // Seed scan locations
        do {
            try PersistenceController.seedDefaultScanLocations(in: modelContainer.mainContext)
        } catch {
            appState.errorMessage = "Failed to seed scan locations: \(error.localizedDescription)"
        }

        // Enable notifications by default on first launch
        if !UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.hasCompletedOnboarding) {
            UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.notificationsEnabled)
            UserDefaults.standard.set(true, forKey: Constants.UserDefaultsKeys.hasCompletedOnboarding)
            _ = await NotificationManager.shared.requestAuthorization()
        }

        // Load manifest + scan
        await appState.loadManifest()
        await appState.performScan()

        // Start auto-scan timer
        appState.startAutoScanTimer()
    }
}
