import Foundation

/// Discovers and parses Ableton Live project (.als) files from configured directories.
actor AbletonProjectScanner {
    struct ScanResult: Sendable {
        let projects: [AbletonProjectParser.ParsedProject]
        let errors: [ScanError]
        let duration: TimeInterval
    }

    struct ScanError: Error, Sendable {
        let url: URL
        let message: String
    }

    enum ScanProgress: Sendable {
        case discovering(directory: String)
        case parsing(current: Int, total: Int, projectName: String)
    }

    enum StreamEvent: Sendable {
        case progress(ScanProgress)
        case batch([AbletonProjectParser.ParsedProject])
        case error(ScanError)
        case completed(duration: TimeInterval)
    }

    private let concurrency: Int

    init(concurrency: Int = Constants.Defaults.scanConcurrency) {
        self.concurrency = concurrency
    }

    /// Performs a full scan of all provided directories for .als files.
    func scan(
        directories: [URL],
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> ScanResult {
        let start = Date()
        var allALSFiles: [URL] = []

        for directory in directories {
            onProgress?(.discovering(directory: directory.lastPathComponent))
            let files = discoverALSFiles(in: directory)
            allALSFiles.append(contentsOf: files)
        }

        let (projects, errors) = await parseProjects(from: allALSFiles, onProgress: onProgress)
        let duration = Date().timeIntervalSince(start)

        return ScanResult(projects: projects, errors: errors, duration: duration)
    }

    /// Streaming scan that yields batches of parsed projects as they complete.
    /// The caller receives `.batch` events every `batchSize` completions.
    func scanStreaming(
        directories: [URL],
        batchSize: Int = 20
    ) -> AsyncStream<StreamEvent> {
        let concurrencyLimit = self.concurrency
        return AsyncStream { continuation in
            Task {
                let start = Date()
                var allALSFiles: [URL] = []

                for directory in directories {
                    continuation.yield(.progress(.discovering(directory: directory.lastPathComponent)))
                    let files = self.discoverALSFiles(in: directory)
                    allALSFiles.append(contentsOf: files)
                }

                let total = allALSFiles.count
                var completed = 0
                var batch: [AbletonProjectParser.ParsedProject] = []
                let parser = AbletonProjectParser()

                await withTaskGroup(of: Result<AbletonProjectParser.ParsedProject, ScanError>.self) { group in
                    var inFlight = 0

                    func processBatch(_ batch: inout [AbletonProjectParser.ParsedProject]) {
                        if !batch.isEmpty {
                            continuation.yield(.batch(batch))
                            batch.removeAll(keepingCapacity: true)
                        }
                    }

                    func handleResult(
                        _ result: Result<AbletonProjectParser.ParsedProject, ScanError>,
                        batch: inout [AbletonProjectParser.ParsedProject],
                        completed: inout Int,
                        total: Int
                    ) {
                        completed += 1
                        switch result {
                        case .success(let project):
                            batch.append(project)
                            continuation.yield(.progress(.parsing(
                                current: completed,
                                total: total,
                                projectName: project.name
                            )))
                            if batch.count >= batchSize {
                                processBatch(&batch)
                            }
                        case .failure(let error):
                            continuation.yield(.error(error))
                            continuation.yield(.progress(.parsing(
                                current: completed,
                                total: total,
                                projectName: error.url.deletingPathExtension().lastPathComponent
                            )))
                        }
                    }

                    for url in allALSFiles {
                        if inFlight >= concurrencyLimit {
                            if let result = await group.next() {
                                inFlight -= 1
                                handleResult(result, batch: &batch, completed: &completed, total: total)
                            }
                        }

                        group.addTask {
                            do {
                                let project = try await parser.parse(fileURL: url)
                                return .success(project)
                            } catch {
                                return .failure(ScanError(url: url, message: error.localizedDescription))
                            }
                        }
                        inFlight += 1
                    }

                    for await result in group {
                        handleResult(result, batch: &batch, completed: &completed, total: total)
                    }

                    // Flush remaining
                    processBatch(&batch)
                }

                let duration = Date().timeIntervalSince(start)
                continuation.yield(.completed(duration: duration))
                continuation.finish()
            }
        }
    }

    /// Incremental scan: only parse files modified after a given date.
    func scanIncremental(
        directories: [URL],
        modifiedAfter: Date?,
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> ScanResult {
        let start = Date()
        var allALSFiles: [URL] = []

        for directory in directories {
            onProgress?(.discovering(directory: directory.lastPathComponent))
            let files = discoverALSFiles(in: directory)
            if let cutoff = modifiedAfter {
                let filtered = files.filter { url in
                    guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                          let modDate = attrs[.modificationDate] as? Date else { return true }
                    return modDate > cutoff
                }
                allALSFiles.append(contentsOf: filtered)
            } else {
                allALSFiles.append(contentsOf: files)
            }
        }

        let (projects, errors) = await parseProjects(from: allALSFiles, onProgress: onProgress)
        let duration = Date().timeIntervalSince(start)

        return ScanResult(projects: projects, errors: errors, duration: duration)
    }

    /// Discovers all .als files recursively in a directory.
    nonisolated func discoverALSFiles(in directory: URL) -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }

        var files: [URL] = []
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension.lowercased() == "als" {
                files.append(url)
            }
        }

        return files.sorted { url1, url2 in
            let size1 = (try? url1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
            let size2 = (try? url2.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
            return size1 < size2
        }
    }

    private func parseProjects(
        from urls: [URL],
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async -> ([AbletonProjectParser.ParsedProject], [ScanError]) {
        var projects: [AbletonProjectParser.ParsedProject] = []
        var errors: [ScanError] = []
        let parser = AbletonProjectParser()
        let total = urls.count
        var completed = 0

        await withTaskGroup(of: Result<AbletonProjectParser.ParsedProject, ScanError>.self) { group in
            var inFlight = 0

            for url in urls {
                if inFlight >= concurrency {
                    if let result = await group.next() {
                        inFlight -= 1
                        completed += 1
                        switch result {
                        case .success(let project):
                            projects.append(project)
                            onProgress?(.parsing(
                                current: completed,
                                total: total,
                                projectName: project.name
                            ))
                        case .failure(let error):
                            errors.append(error)
                            onProgress?(.parsing(
                                current: completed,
                                total: total,
                                projectName: error.url.deletingPathExtension().lastPathComponent
                            ))
                        }
                    }
                }

                group.addTask {
                    do {
                        let project = try await parser.parse(fileURL: url)
                        return .success(project)
                    } catch {
                        return .failure(ScanError(url: url, message: error.localizedDescription))
                    }
                }
                inFlight += 1
            }

            for await result in group {
                completed += 1
                switch result {
                case .success(let project):
                    projects.append(project)
                    onProgress?(.parsing(
                        current: completed,
                        total: total,
                        projectName: project.name
                    ))
                case .failure(let error):
                    errors.append(error)
                    onProgress?(.parsing(
                        current: completed,
                        total: total,
                        projectName: error.url.deletingPathExtension().lastPathComponent
                    ))
                }
            }
        }

        return (projects, errors)
    }
}
