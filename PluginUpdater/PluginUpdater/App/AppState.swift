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
    private let vendorURLResolver = VendorURLResolver()

    /// Plist fields from most recent scan, keyed by bundleID.
    /// Used by VendorURLResolver for URL extraction from plist metadata.
    private var scannedPlistFields: [String: [String: String]] = [:]

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

        // Load cask mappings + vendor URL overrides
        await versionChecker.loadMappings()
        await vendorURLResolver.loadOverrides()
    }

    /// Checks for available updates via the Homebrew Formulae API
    /// and resolves vendor URLs for all plugins.
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

        // Resolve vendor URLs for plugins missing a download link
        await resolveVendorURLs(for: plugins)

        // Count plugins with available updates
        updatesAvailableCount = plugins.filter { plugin in
            guard let entry = manifestEntries[plugin.bundleIdentifier] else { return false }
            return entry.latestVersion.isNewerVersion(than: plugin.currentVersion)
        }.count
    }

    /// Uses VendorURLResolver to find URLs for plugins without download links.
    /// Tries: hardcoded overrides → plist URLs → reverse-domain → search fallback.
    /// Deduplicates by vendor prefix and resolves in parallel batches.
    private func resolveVendorURLs(for plugins: [Plugin]) async {
        // Group plugins by vendor prefix — only resolve once per vendor
        var prefixToPlugins: [String: [(bundleID: String, version: String, vendor: String)]] = [:]

        for plugin in plugins {
            let bundleID = plugin.bundleIdentifier

            // Skip if already has a download URL
            if let entry = manifestEntries[bundleID], entry.downloadURL != nil {
                continue
            }

            let prefix = bundleIDPrefix(bundleID)
            prefixToPlugins[prefix, default: []].append(
                (bundleID: bundleID, version: plugin.currentVersion, vendor: plugin.vendorName)
            )
        }

        guard !prefixToPlugins.isEmpty else { return }

        // Resolve one representative per vendor prefix, in parallel (bounded to 6)
        let representatives = prefixToPlugins.map { (prefix: $0.key, plugins: $0.value) }

        await withTaskGroup(of: (String, [String], String?).self) { group in
            var inFlight = 0

            for rep in representatives {
                if inFlight >= 6 {
                    if let result = await group.next() {
                        applyResolvedURL(result.0, bundleIDs: result.1, url: result.2)
                        inFlight -= 1
                    }
                }

                let first = rep.plugins[0]
                let allBundleIDs = rep.plugins.map(\.bundleID)
                let plistFields = scannedPlistFields[first.bundleID]

                group.addTask {
                    let url = await self.vendorURLResolver.resolve(
                        bundleID: first.bundleID,
                        plistFields: plistFields,
                        vendorName: first.vendor
                    )
                    return (rep.prefix, allBundleIDs, url)
                }
                inFlight += 1
            }

            for await result in group {
                applyResolvedURL(result.0, bundleIDs: result.1, url: result.2)
            }
        }
    }

    /// Applies a resolved vendor URL to all plugins sharing the same vendor prefix.
    private func applyResolvedURL(_ prefix: String, bundleIDs: [String], url: String?) {
        guard let url else { return }
        for bundleID in bundleIDs {
            let existingEntry = manifestEntries[bundleID]
            manifestEntries[bundleID] = UpdateManifestEntry(
                bundleIdentifier: bundleID,
                latestVersion: existingEntry?.latestVersion ?? "0.0.0",
                downloadURL: url,
                releaseNotes: existingEntry?.releaseNotes,
                releaseDate: existingEntry?.releaseDate
            )
        }
    }

    /// Extracts the first two parts of a bundle ID: "com.fabfilter.ProQ" → "com.fabfilter"
    private func bundleIDPrefix(_ bundleID: String) -> String {
        let parts = bundleID.split(separator: ".", maxSplits: 2)
        if parts.count >= 2 {
            return "\(parts[0]).\(parts[1])"
        }
        return bundleID
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

            // Cache plist fields for vendor URL resolution
            scannedPlistFields = [:]
            for metadata in scanResult.plugins {
                scannedPlistFields[metadata.bundleIdentifier] = metadata.plistFields
            }

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

            // Check for available updates + resolve vendor URLs
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

            // Update plist fields cache with incremental results
            for metadata in scanResult.plugins {
                scannedPlistFields[metadata.bundleIdentifier] = metadata.plistFields
            }

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
