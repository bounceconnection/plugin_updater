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
    var updatesAvailableCount = 0

    private(set) var modelContainer: ModelContainer
    private var fileMonitor: FileSystemMonitor?
    private var autoScanTimer: Timer?
    private var isScanInProgress = false
    private let manifestManager = ManifestManager()
    private let versionChecker = VersionChecker()

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

        // Load cask mappings for automatic version checking
        await versionChecker.loadMappings()
    }

    /// Checks for available updates via the Homebrew Formulae API
    /// and merges results into manifestEntries.
    func checkForUpdates() async {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<Plugin>(
            predicate: #Predicate { !$0.isRemoved }
        )
        guard let plugins = try? context.fetch(descriptor) else { return }

        // Build lookup: bundleID -> installedVersion
        var installed: [String: String] = [:]
        for plugin in plugins {
            installed[plugin.bundleIdentifier] = plugin.currentVersion
        }

        let updates = await versionChecker.checkForUpdates(installedPlugins: installed)

        // Merge: Homebrew data overrides bundled manifest
        for (bundleID, entry) in updates {
            manifestEntries[bundleID] = entry
        }

        // Fill in vendor URLs as fallback for plugins without a download URL
        for plugin in plugins {
            let bundleID = plugin.bundleIdentifier
            if let entry = manifestEntries[bundleID], entry.downloadURL == nil {
                if let vendorURL = await versionChecker.vendorURL(for: bundleID) {
                    manifestEntries[bundleID] = UpdateManifestEntry(
                        bundleIdentifier: bundleID,
                        latestVersion: entry.latestVersion,
                        downloadURL: vendorURL,
                        releaseNotes: entry.releaseNotes,
                        releaseDate: entry.releaseDate
                    )
                }
            } else if manifestEntries[bundleID] == nil {
                // No manifest entry at all — create one with just the vendor URL
                if let vendorURL = await versionChecker.vendorURL(for: bundleID) {
                    manifestEntries[bundleID] = UpdateManifestEntry(
                        bundleIdentifier: bundleID,
                        latestVersion: plugin.currentVersion,
                        downloadURL: vendorURL,
                        releaseNotes: nil,
                        releaseDate: nil
                    )
                }
            }
        }

        // Count plugins with available updates
        updatesAvailableCount = plugins.filter { plugin in
            guard let entry = manifestEntries[plugin.bundleIdentifier] else { return false }
            return entry.latestVersion.isNewerVersion(than: plugin.currentVersion)
        }.count
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

            // Check for available updates via Homebrew API
            await checkForUpdates()

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

    // MARK: - Auto-Scan Timer

    func startAutoScanTimer() {
        let minutes = UserDefaults.standard.integer(forKey: Constants.UserDefaultsKeys.scanFrequency)
        let interval = minutes > 0 ? minutes : Constants.Defaults.scanFrequencyMinutes
        updateAutoScanInterval(minutes: interval)
    }

    func updateAutoScanInterval(minutes: Int) {
        autoScanTimer?.invalidate()
        autoScanTimer = nil

        guard minutes > 0 else { return }

        let interval = TimeInterval(minutes * 60)
        autoScanTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.performScan()
            }
        }
    }

    // MARK: - Export

    func exportPluginListCSV() -> String {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<Plugin>(
            predicate: #Predicate { !$0.isRemoved },
            sortBy: [SortDescriptor(\.name)]
        )
        guard let plugins = try? context.fetch(descriptor) else { return "" }

        var csv = "Name,Vendor,Format,Version,Bundle ID,Path\n"
        for plugin in plugins {
            let name = plugin.name.csvEscaped
            let vendor = plugin.vendorName.csvEscaped
            let format = plugin.format.displayName
            let version = plugin.currentVersion
            let bundleID = plugin.bundleIdentifier
            let path = plugin.path.csvEscaped
            csv += "\(name),\(vendor),\(format),\(version),\(bundleID),\(path)\n"
        }
        return csv
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
