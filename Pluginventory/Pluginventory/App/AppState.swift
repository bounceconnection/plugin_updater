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
    var availableAppUpdate: AppUpdateChecker.AppUpdate?
    var lastManifestRefresh: Date?
    var isProjectScanning = false
    var projectScanProgress: Double = 0
    var projectScanStatusText: String = ""
    var totalProjectCount = 0
    var projectsWithMissingPlugins = 0

    private(set) var modelContainer: ModelContainer
    private var fileMonitor: FileSystemMonitor?
    private var projectFileMonitor: FileSystemMonitor?
    private var autoScanTimer: Timer?
    private var isScanInProgress = false
    private let manifestManager = ManifestManager()
    private let versionChecker = VersionChecker()
    private let vendorURLResolver = VendorURLResolver()
    private let appUpdateChecker = AppUpdateChecker()
    private let manifestCacheManager = ManifestCacheManager()
    private var prefetchTask: Task<Void, Never>?

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

    /// Loads cached manifest entries from disk for instant startup display.
    func loadCachedManifestEntries() async {
        guard let cached = await manifestCacheManager.load() else { return }
        // Only apply cached entries that aren't already populated by the bundled manifest
        for (bundleID, entry) in cached.entries where manifestEntries[bundleID] == nil {
            manifestEntries[bundleID] = entry
        }
        lastManifestRefresh = cached.lastRefreshed
        AppLogger.shared.info(
            "Loaded \(cached.entries.count) cached manifest entries (refreshed \(cached.lastRefreshed.formatted(.relative(presentation: .named))))",
            category: "updates"
        )
    }

    /// Saves current manifest entries to disk cache for next launch.
    func saveCachedManifestEntries() async {
        await manifestCacheManager.save(manifestEntries)
        lastManifestRefresh = .now
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

        AppLogger.shared.info("Update check started for \(installed.count) plugins", category: "updates")

        let updates = await versionChecker.checkForUpdates(installedPlugins: installed)

        // Merge: Homebrew data overrides bundled manifest
        for (bundleID, entry) in updates {
            manifestEntries[bundleID] = entry
        }

        // Resolve vendor URLs for plugins missing a download link
        await resolveVendorURLs(for: plugins)

        // Count plugins with available updates
        updatesAvailableCount = plugins.filter { plugin in
            guard let entry = manifestEntries[plugin.bundleIdentifier],
                  !entry.latestVersion.isEmpty else { return false }
            return entry.latestVersion.isNewerVersion(than: plugin.currentVersion)
        }.count

        AppLogger.shared.info("Update check complete — \(updatesAvailableCount) updates available", category: "updates")

        // Cache manifest entries for instant display on next launch
        await saveCachedManifestEntries()
    }

    /// Checks the GitHub Releases API for a newer version of Pluginventory.
    func checkForAppUpdate() async {
        availableAppUpdate = await appUpdateChecker.checkForUpdate(
            currentVersion: AppVersion.version
        )
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
    /// Only updates the download URL — does not create fake version entries.
    private func applyResolvedURL(_ prefix: String, bundleIDs: [String], url: String?) {
        guard let url else { return }
        for bundleID in bundleIDs {
            if let existing = manifestEntries[bundleID] {
                // Update existing entry with the resolved URL
                manifestEntries[bundleID] = UpdateManifestEntry(
                    bundleIdentifier: bundleID,
                    latestVersion: existing.latestVersion,
                    downloadURL: url,
                    releaseNotes: existing.releaseNotes,
                    releaseDate: existing.releaseDate
                )
            } else {
                // No version data — store URL-only entry so the Download column works
                manifestEntries[bundleID] = UpdateManifestEntry(
                    bundleIdentifier: bundleID,
                    latestVersion: "",
                    downloadURL: url,
                    releaseNotes: nil,
                    releaseDate: nil
                )
            }
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
        prefetchTask?.cancel()
        prefetchTask = nil
        isScanning = true
        errorMessage = nil
        scanProgress = 0

        do {
            let directories = try enabledScanDirectories()

            guard !directories.isEmpty else {
                errorMessage = "No scan locations configured"
                AppLogger.shared.error("Scan aborted — no scan locations configured", category: "scan")
                isScanning = false
                isScanInProgress = false
                return
            }

            AppLogger.shared.info("Scan started — \(directories.count) directories", category: "scan")

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

            // Prefetch plugin images in the background
            prefetchImages()

            // Start monitoring after first successful scan
            startMonitoring(directories: directories)
        } catch {
            let msg = "Scan failed: \(error.localizedDescription)"
            errorMessage = msg
            AppLogger.shared.error(msg, category: "scan")
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

    // MARK: - Image Prefetching

    /// Cancels any running image prefetch task.
    func cancelImagePrefetch() {
        prefetchTask?.cancel()
        prefetchTask = nil
    }

    /// Warms the image cache in the background for all unique plugins.
    private func prefetchImages() {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<Plugin>(
            predicate: #Predicate { !$0.isRemoved }
        )
        guard let plugins = try? context.fetch(descriptor) else { return }

        // Copy plugin data into plain tuples (SwiftData objects aren't Sendable)
        struct PluginInfo: Hashable {
            let name: String
            let vendor: String
            let bundleID: String
            let path: String
            let vendorURL: String?
            var sharedKey: String { "\(vendor.lowercased())_\(name.lowercased())" }
        }

        var seen = Set<String>()
        var uniquePlugins: [PluginInfo] = []
        for plugin in plugins {
            let info = PluginInfo(
                name: plugin.name,
                vendor: plugin.vendorName,
                bundleID: plugin.bundleIdentifier,
                path: plugin.path,
                vendorURL: manifestEntries[plugin.bundleIdentifier]?.downloadURL
            )
            if seen.insert(info.sharedKey).inserted {
                uniquePlugins.append(info)
            }
        }

        AppLogger.shared.info("Image prefetch starting for \(uniquePlugins.count) unique plugins", category: "images")

        prefetchTask = Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                var inFlight = 0
                for info in uniquePlugins {
                    if Task.isCancelled { break }

                    // Skip already-cached images
                    let cached = await PluginImageService.shared.hasCachedImage(
                        pluginName: info.name,
                        vendorName: info.vendor,
                        bundleID: info.bundleID
                    )
                    if cached { continue }

                    if inFlight >= 3 {
                        _ = await group.next()
                        inFlight -= 1
                    }

                    group.addTask {
                        _ = await PluginImageService.shared.image(
                            pluginName: info.name,
                            vendorName: info.vendor,
                            bundleID: info.bundleID,
                            pluginPath: info.path,
                            vendorURL: info.vendorURL
                        )
                    }
                    inFlight += 1
                }
            }

            if !Task.isCancelled {
                await MainActor.run {
                    AppLogger.shared.info("Image prefetch complete", category: "images")
                }
            }
        }
    }

    // MARK: - Project Scanning

    func performProjectScan() async {
        guard !isProjectScanning else { return }
        isProjectScanning = true
        projectScanProgress = 0
        projectScanStatusText = "Discovering projects..."

        // Set verbose logging from UserDefaults
        AppLogger.shared.verbose = UserDefaults.standard.bool(forKey: Constants.UserDefaultsKeys.debugVerboseLogging)

        do {
            let directories = projectScanDirectories()
            guard !directories.isEmpty else {
                isProjectScanning = false
                projectScanStatusText = ""
                return
            }

            let scanStart = Date()

            AppLogger.shared.info(
                "Project scan started — \(directories.count) directories",
                category: "scan"
            )

            let scanner = AbletonProjectScanner()
            let reconciler = ProjectReconciler(modelContainer: modelContainer)
            try await reconciler.prepareForScan()
            let stream = await scanner.scanStreaming(directories: directories)
            var allScannedPaths: Set<String> = []
            var errorCount = 0

            for await event in stream {
                switch event {
                case .progress(let progress):
                    switch progress {
                    case .discovering(let dir):
                        projectScanStatusText = "Scanning \(dir)..."
                        projectScanProgress = 0.1
                    case .parsing(let current, let total, let name):
                        projectScanStatusText = "Parsing \(name) (\(current)/\(total))"
                        projectScanProgress = 0.1 + 0.7 * Double(current) / Double(max(total, 1))
                    }

                case .batch(let projects):
                    allScannedPaths.formUnion(projects.map(\.filePath))
                    _ = try await reconciler.reconcile(parsedProjects: projects, fullScan: false)

                case .error:
                    errorCount += 1

                case .completed(let duration):
                    AppLogger.shared.info(
                        "Project parsing complete in \(String(format: "%.1f", duration))s",
                        category: "scan"
                    )
                }
            }

            // Final removal sweep — mark projects not seen in this scan
            projectScanStatusText = "Cleaning up..."
            projectScanProgress = 0.85
            let removedCount = try await reconciler.markMissingProjects(scannedPaths: allScannedPaths)
            await reconciler.finishScan()
            if removedCount > 0 {
                AppLogger.shared.info(
                    "Marked \(removedCount) missing projects as removed",
                    category: "scan"
                )
            }

            projectScanProgress = 0.95

            let countDescriptor = FetchDescriptor<AbletonProject>(
                predicate: #Predicate { !$0.isRemoved }
            )
            totalProjectCount = (try? modelContainer.mainContext.fetchCount(countDescriptor)) ?? 0

            let allProjects = try? modelContainer.mainContext.fetch(
                FetchDescriptor<AbletonProject>(
                    predicate: #Predicate { !$0.isRemoved }
                )
            )
            projectsWithMissingPlugins = allProjects?
                .filter { $0.missingPluginCount > 0 }.count ?? 0

            projectScanProgress = 1.0

            let totalDuration = Date().timeIntervalSince(scanStart)
            AppLogger.shared.info(
                "Project scan complete — \(totalProjectCount) projects, \(errorCount) errors in \(String(format: "%.1f", totalDuration))s",
                category: "scan"
            )
        } catch {
            AppLogger.shared.error(
                "Project scan failed: \(error.localizedDescription)",
                category: "scan"
            )
        }

        projectScanStatusText = ""
        isProjectScanning = false
    }

    func projectScanDirectories() -> [URL] {
        let saved = UserDefaults.standard.stringArray(
            forKey: Constants.UserDefaultsKeys.projectScanDirectories
        )
        let paths = saved ?? Constants.defaultProjectScanDirectories
        return paths.map { URL(fileURLWithPath: $0) }
    }

    func startProjectMonitoring() {
        guard UserDefaults.standard.bool(
            forKey: Constants.UserDefaultsKeys.monitorProjectDirectories
        ) else { return }

        projectFileMonitor?.stopMonitoring()
        let monitor = FileSystemMonitor()
        monitor.onDirectoriesChanged = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.performProjectScan()
            }
        }
        monitor.startMonitoring(directories: projectScanDirectories())
        projectFileMonitor = monitor
    }

    func stopProjectMonitoring() {
        projectFileMonitor?.stopMonitoring()
        projectFileMonitor = nil
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

        AppLogger.shared.info(
            "Scan complete — \(totalPluginCount) plugins, \(errors.count) errors",
            category: "scan"
        )

        if !errors.isEmpty {
            errorMessage = "\(errors.count) plugin(s) could not be read"
            AppLogger.shared.error("\(errors.count) plugin(s) could not be read", category: "scan")
        }
    }
}
