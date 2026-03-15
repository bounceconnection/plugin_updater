import Foundation
import OSLog

/// Lightweight singleton logger that writes to both Apple's OSLog and a daily rolling text file.
/// Log files are stored at ~/Library/Logs/Pluginventory/ and kept for 7 days.
final class AppLogger {
    static let shared = AppLogger()

    /// When true, per-plugin matching details are logged. Off by default.
    /// Toggle via `defaults write com.bounceconnection.Pluginventory debugVerboseLogging -bool YES`
    var verbose: Bool = false

    private let osLog = Logger(subsystem: "com.bounceconnection.Pluginventory", category: "app")
    private let queue = DispatchQueue(label: "com.bounceconnection.Pluginventory.logger", qos: .utility)
    private var fileHandle: FileHandle?
    private var currentLogDate: String = ""

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    let logsDirectoryURL: URL = {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Logs/Pluginventory", isDirectory: true)
    }()

    private init() {
        queue.async { self.setup() }
    }

    // MARK: - Public API

    func info(_ message: String, category: String = "app") {
        log(message, level: "INFO ", category: category)
    }

    func error(_ message: String, category: String = "app") {
        log(message, level: "ERROR", category: category)
    }

    func debug(_ message: String, category: String = "app") {
        log(message, level: "DEBUG", category: category)
    }

    // MARK: - Private

    private func log(_ message: String, level: String, category: String) {
        switch level {
        case "INFO ": osLog.info("[\(category)] \(message)")
        case "ERROR": osLog.error("[\(category)] \(message)")
        default:      osLog.debug("[\(category)] \(message)")
        }

        queue.async { self.writeToFile(message, level: level, category: category) }
    }

    private func setup() {
        let fm = FileManager.default
        try? fm.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)
        pruneOldLogs()
        openFileForToday()
    }

    private func pruneOldLogs() {
        let fm = FileManager.default
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        guard let files = try? fm.contentsOfDirectory(
            at: logsDirectoryURL,
            includingPropertiesForKeys: [.creationDateKey]
        ) else { return }

        for file in files where file.pathExtension == "log" {
            if let attrs = try? file.resourceValues(forKeys: [.creationDateKey]),
               let created = attrs.creationDate,
               created < cutoff {
                try? fm.removeItem(at: file)
            }
        }
    }

    private func openFileForToday() {
        let dateString = Self.dayFormatter.string(from: Date())
        guard dateString != currentLogDate else { return }

        fileHandle?.closeFile()

        let fileURL = logsDirectoryURL.appendingPathComponent("pluginventory-\(dateString).log")
        let fm = FileManager.default
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }

        fileHandle = try? FileHandle(forWritingTo: fileURL)
        fileHandle?.seekToEndOfFile()
        currentLogDate = dateString
    }

    private func writeToFile(_ message: String, level: String, category: String) {
        let dateString = Self.dayFormatter.string(from: Date())
        if dateString != currentLogDate {
            openFileForToday()
        }

        let timestamp = Self.timestampFormatter.string(from: Date())
        let line = "[\(timestamp)] [\(level)] [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        fileHandle?.write(data)
    }
}
