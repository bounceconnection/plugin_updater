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
            ContentView()
                .environment(appState)
                .task {
                    await initialSetup()
                }
        }
        .modelContainer(modelContainer)

        MenuBarExtra("Plugin Updater", systemImage: "puzzlepiece.extension") {
            MenuBarPlaceholderView()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsPlaceholderView()
                .environment(appState)
        }
        .modelContainer(modelContainer)
    }

    @MainActor
    private func initialSetup() async {
        do {
            try PersistenceController.seedDefaultScanLocations(in: modelContainer.mainContext)
        } catch {
            appState.errorMessage = "Failed to seed scan locations: \(error.localizedDescription)"
        }
        await appState.performScan()
    }
}

// MARK: - Placeholder views (will be replaced in later phases)

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Query(filter: #Predicate<Plugin> { !$0.isRemoved }) private var plugins: [Plugin]

    var body: some View {
        NavigationSplitView {
            List {
                ForEach(PluginFormat.allCases) { format in
                    Label(format.displayName, systemImage: "puzzlepiece.extension")
                }
            }
            .navigationTitle("Plugins")
        } detail: {
            VStack(spacing: 16) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Plugin Updater")
                    .font(.title)
                Text("\(plugins.count) plugins tracked")
                    .foregroundStyle(.secondary)
                if appState.isScanning {
                    ProgressView(value: appState.scanProgress) {
                        Text("Scanning...")
                    }
                    .frame(width: 200)
                } else {
                    Button("Scan Now") {
                        Task { await appState.performScan() }
                    }
                }
                if let error = appState.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if !appState.recentChanges.isEmpty {
                    Divider()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Recent Changes")
                            .font(.headline)
                        ForEach(appState.recentChanges, id: \.self) { change in
                            Text(change)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 300)
        }
    }
}

struct MenuBarPlaceholderView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Plugin Updater")
                .font(.headline)
            Divider()
            Text("\(appState.totalPluginCount) plugins")
                .font(.subheadline)
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

struct SettingsPlaceholderView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Form {
            Text("Settings will be available in a future update.")
        }
        .padding()
        .frame(width: 400, height: 200)
    }
}
