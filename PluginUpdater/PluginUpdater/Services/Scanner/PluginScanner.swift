import Foundation

actor PluginScanner {
    struct ScanResult: Sendable {
        let plugins: [PluginMetadata]
        let errors: [ScanError]
        let duration: TimeInterval
    }

    struct ScanError: Error, Sendable {
        let url: URL
        let message: String
    }

    private let concurrency: Int

    init(concurrency: Int = Constants.Defaults.scanConcurrency) {
        self.concurrency = concurrency
    }

    /// Performs a full scan of all provided directories.
    func scan(directories: [URL]) async -> ScanResult {
        let start = Date()
        var allBundleURLs: [URL] = []

        for directory in directories {
            let bundles = discoverBundles(in: directory)
            allBundleURLs.append(contentsOf: bundles)
        }

        let (plugins, errors) = await extractMetadata(from: allBundleURLs)
        let duration = Date().timeIntervalSince(start)

        return ScanResult(plugins: plugins, errors: errors, duration: duration)
    }

    /// Scans only the given directories (for incremental/targeted scans).
    func scanIncremental(directories: [URL]) async -> ScanResult {
        await scan(directories: directories)
    }

    /// Discovers all plugin bundles (recursively) in a directory.
    /// Handles vendor subdirectories like /VST3/Eventide/Plugin.vst3
    nonisolated func discoverBundles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }

        var bundles: [URL] = []
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let url = enumerator.nextObject() as? URL {
            if url.isPluginBundle {
                bundles.append(url)
                // Don't descend into plugin bundles (they're directories themselves)
                enumerator.skipDescendants()
            }
        }

        return bundles
    }

    /// Extracts metadata from all bundle URLs using bounded concurrency via TaskGroup.
    private func extractMetadata(from urls: [URL]) async -> ([PluginMetadata], [ScanError]) {
        var plugins: [PluginMetadata] = []
        var errors: [ScanError] = []

        // Use TaskGroup with bounded concurrency
        await withTaskGroup(of: Result<PluginMetadata, ScanError>.self) { group in
            var inFlight = 0

            for url in urls {
                // Throttle: wait for a result before adding more if at capacity
                if inFlight >= concurrency {
                    if let result = await group.next() {
                        inFlight -= 1
                        switch result {
                        case .success(let metadata):
                            plugins.append(metadata)
                        case .failure(let error):
                            errors.append(error)
                        }
                    }
                }

                group.addTask {
                    do {
                        let metadata = try BundleMetadataExtractor.extract(from: url)
                        return .success(metadata)
                    } catch {
                        return .failure(ScanError(url: url, message: error.localizedDescription))
                    }
                }
                inFlight += 1
            }

            // Collect remaining results
            for await result in group {
                switch result {
                case .success(let metadata):
                    plugins.append(metadata)
                case .failure(let error):
                    errors.append(error)
                }
            }
        }

        return (plugins, errors)
    }
}
