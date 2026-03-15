import Testing
import Foundation
@testable import Pluginventory

@Suite("AbletonProjectScanner Tests")
struct AbletonProjectScannerTests {

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScannerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    private func createFile(at dir: URL, name: String, size: Int) throws {
        let data = Data(repeating: 0, count: size)
        try data.write(to: dir.appendingPathComponent(name))
    }

    @Test("discoverALSFiles finds all .als files recursively")
    func discoverALSFilesFindsAllFiles() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }
        let subdir = dir.appendingPathComponent("SubProject")
        try FileManager.default.createDirectory(at: subdir, withIntermediateDirectories: true)

        try createFile(at: dir, name: "project1.als", size: 100)
        try createFile(at: dir, name: "project2.als", size: 200)
        try createFile(at: subdir, name: "project3.als", size: 300)

        let scanner = AbletonProjectScanner()
        let files = scanner.discoverALSFiles(in: dir)
        #expect(files.count == 3)
    }

    @Test("discoverALSFiles ignores non-.als files")
    func discoverALSFilesIgnoresNonALSFiles() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir, name: "readme.txt", size: 50)
        try createFile(at: dir, name: "audio.wav", size: 100)
        try createFile(at: dir, name: "project.als", size: 150)

        let scanner = AbletonProjectScanner()
        let files = scanner.discoverALSFiles(in: dir)
        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent == "project.als")
    }

    @Test("discoverALSFiles skips hidden files and directories")
    func discoverALSFilesSkipsHiddenFiles() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir, name: ".hidden.als", size: 100)
        try createFile(at: dir, name: "visible.als", size: 100)
        let hiddenDir = dir.appendingPathComponent(".hidden_folder")
        try FileManager.default.createDirectory(at: hiddenDir, withIntermediateDirectories: true)
        try createFile(at: hiddenDir, name: "inside.als", size: 100)

        let scanner = AbletonProjectScanner()
        let files = scanner.discoverALSFiles(in: dir)
        #expect(files.count == 1)
        #expect(files.first?.lastPathComponent == "visible.als")
    }

    @Test("discoverALSFiles returns empty for missing directory")
    func discoverALSFilesReturnsEmptyForMissingDirectory() {
        let scanner = AbletonProjectScanner()
        let files = scanner.discoverALSFiles(in: URL(fileURLWithPath: "/nonexistent/path/\(UUID().uuidString)"))
        #expect(files.isEmpty)
    }

    @Test("discoverALSFiles returns files sorted by size ascending")
    func discoverALSFilesSortedBySize() throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        try createFile(at: dir, name: "large.als", size: 10000)
        try createFile(at: dir, name: "small.als", size: 100)
        try createFile(at: dir, name: "medium.als", size: 1000)

        let scanner = AbletonProjectScanner()
        let files = scanner.discoverALSFiles(in: dir)
        #expect(files.count == 3)

        let sizes = files.compactMap {
            (try? $0.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        }
        #expect(sizes == sizes.sorted())
    }

    // MARK: - Streaming Scan Tests

    @Test("scanStreaming yields batches and completed event")
    func scanStreamingYieldsBatchesAndCompleted() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        // Create dummy .als files (these won't parse as valid gzip XML, so we expect errors)
        for i in 0..<5 {
            try createFile(at: dir, name: "project\(i).als", size: 100 + i * 50)
        }

        let scanner = AbletonProjectScanner()
        let stream = await scanner.scanStreaming(directories: [dir], batchSize: 2)

        var progressEvents: [AbletonProjectScanner.ScanProgress] = []
        var errorCount = 0
        var completedDuration: TimeInterval?

        for await event in stream {
            switch event {
            case .progress(let p):
                progressEvents.append(p)
            case .batch:
                break // May not get batches since files aren't valid gzip
            case .error:
                errorCount += 1
            case .completed(let duration):
                completedDuration = duration
            }
        }

        // Should always get a completed event
        #expect(completedDuration != nil)
        // Should get at least a discovering progress event
        let hasDiscovering = progressEvents.contains {
            if case .discovering = $0 { return true }
            return false
        }
        #expect(hasDiscovering)
        // All 5 files should produce either a batch or error
        #expect(errorCount + progressEvents.filter {
            if case .parsing = $0 { return true }
            return false
        }.count >= 5)
    }

    @Test("scanStreaming with empty directory yields completed with no batches")
    func scanStreamingEmptyDirectory() async throws {
        let dir = try makeTempDir()
        defer { cleanup(dir) }

        let scanner = AbletonProjectScanner()
        let stream = await scanner.scanStreaming(directories: [dir], batchSize: 5)

        var batchCount = 0
        var completedDuration: TimeInterval?

        for await event in stream {
            switch event {
            case .batch:
                batchCount += 1
            case .completed(let duration):
                completedDuration = duration
            default:
                break
            }
        }

        #expect(batchCount == 0)
        #expect(completedDuration != nil)
    }

    @Test("scanStreaming with nonexistent directory yields completed without errors")
    func scanStreamingNonexistentDirectory() async throws {
        let scanner = AbletonProjectScanner()
        let stream = await scanner.scanStreaming(
            directories: [URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")],
            batchSize: 5
        )

        var errorCount = 0
        var completedDuration: TimeInterval?

        for await event in stream {
            switch event {
            case .error:
                errorCount += 1
            case .completed(let duration):
                completedDuration = duration
            default:
                break
            }
        }

        // No files discovered → no parse errors, just a completed event
        #expect(errorCount == 0)
        #expect(completedDuration != nil)
    }
}
