import SwiftUI
import SwiftData

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

        MenuBarExtra("Plugin Updater", systemImage: "puzzlepiece.extension") {
            MenuBarPopoverView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
        .modelContainer(modelContainer)
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
    }
}
