import Foundation
import SwiftUI
import SwiftData

@Observable @MainActor
final class AppState {
    var isScanning = false
    var lastScanDate: Date?
    var totalPluginCount = 0
    var recentChanges: [String] = []
    var scanProgress: Double = 0
    var errorMessage: String?
    var manifestEntries: [String: UpdateManifestEntry] = [:]

    private(set) var modelContainer: ModelContainer
    private var fileMonitor: FileSystemMonitor?
    private var isScanInProgress = false
    private let manifestManager = ManifestManager()

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.lastScanDate = UserDefaults.standard.object(forKey: Constants.UserDefaultsKeys.lastScanDate) as? Date
    }

    // MARK: - Manifest

    func loadManifest() async {
        await manifestManager.loadBundledManifest()

        let remoteURL = UserDefaults.standard.string(forKey: Constants.UserDefaultsKeys.manifestURL) ?? ""
        if !remoteURL.isEmpty {
            await manifestManager.fetchRemote(from: remoteURL)
        }

        manifestEntries = await manifestManager.allEntries()
    }

    // MARK: - Full Scan

    func performScan() async {
        guard !isScanInProgress else { return }
        isScanInProgress = true
        isScanning = true
        errorMessage = nil
        scanProgress = 0

        do {
            let directories = try enabledScanDirectories()

            guard !directories.isEmpty else {
                errorMessage = "No scan locations configured"
                isScanning = false
                isScanInProgress = false
                return
            }

            // Scan for plugin bundles
            scanProgress = 0.2
            let scanner = PluginScanner()
            let scanResult = await scanner.scan(directories: directories)

            // Reconcile with persistent store (full scan marks missing plugins as removed)
            scanProgress = 0.7
            let reconciler = PluginReconciler(modelContainer: modelContainer)
            let result = try await reconciler.reconcile(scannedPlugins: scanResult.plugins, fullScan: true)

            // Update UI state
            scanProgress = 1.0
            applyResult(result, errors: scanResult.errors)

            // Send notifications (skip first scan — too noisy)
            if lastScanDate != nil {
                NotificationManager.shared.notifyChanges(result.changes)
            }

            // Start monitoring after first successful scan
            startMonitoring(directories: directories)
        } catch {
            errorMessage = "Scan failed: \(error.localizedDescription)"
        }

        isScanning = false
        isScanInProgress = false
    }

    // MARK: - Incremental Scan (triggered by FSEvents)

    func performIncrementalScan(directories: [URL]) async {
        guard !isScanInProgress else { return }
        isScanInProgress = true
        // No UI indication — incremental scans run silently in the background

        do {
            let scanner = PluginScanner()
            let scanResult = await scanner.scan(directories: directories)

            let reconciler = PluginReconciler(modelContainer: modelContainer)
            let result = try await reconciler.reconcile(scannedPlugins: scanResult.plugins, fullScan: false)

            applyResult(result, errors: scanResult.errors)

            // Notify for incremental changes
            NotificationManager.shared.notifyChanges(result.changes)
        } catch {
            // Silently ignore incremental scan failures
        }

        isScanInProgress = false
    }

    // MARK: - File System Monitoring

    func startMonitoring(directories: [URL]) {
        fileMonitor?.stopMonitoring()

        let monitor = FileSystemMonitor()
        monitor.onDirectoriesChanged = { [weak self] changedDirs in
            guard let self else { return }
            Task { @MainActor in
                await self.performIncrementalScan(directories: changedDirs)
            }
        }
        monitor.startMonitoring(directories: directories)
        fileMonitor = monitor
    }

    func stopMonitoring() {
        fileMonitor?.stopMonitoring()
        fileMonitor = nil
    }

    // MARK: - Private

    private func enabledScanDirectories() throws -> [URL] {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ScanLocation>(
            predicate: #Predicate { $0.isEnabled }
        )
        return try context.fetch(descriptor).map(\.url)
    }

    private func applyResult(_ result: PluginReconciler.ReconciliationResult, errors: [PluginScanner.ScanError]) {
        lastScanDate = .now
        UserDefaults.standard.set(Date.now, forKey: Constants.UserDefaultsKeys.lastScanDate)

        let countDescriptor = FetchDescriptor<Plugin>(
            predicate: #Predicate { !$0.isRemoved }
        )
        totalPluginCount = (try? modelContainer.mainContext.fetchCount(countDescriptor)) ?? result.totalProcessed

        // Only update recent changes when there are actual changes to show
        if !result.changes.isEmpty {
            recentChanges = result.changes.prefix(20).map { change in
                switch change.changeType {
                case .added:
                    "New: \(change.pluginName)"
                case .updated(let old, let new):
                    "Updated: \(change.pluginName) \(old) → \(new)"
                case .removed:
                    "Removed: \(change.pluginName)"
                case .reappeared:
                    "Reappeared: \(change.pluginName)"
                }
            }
        }

        if !errors.isEmpty {
            errorMessage = "\(errors.count) plugin(s) could not be read"
        }
    }
}
