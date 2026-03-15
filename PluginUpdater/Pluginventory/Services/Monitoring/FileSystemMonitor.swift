import Foundation
import CoreServices

final class FileSystemMonitor {
    private var stream: FSEventStreamRef?
    private let debounceInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.bounceconnection.Pluginventory.fsmonitor", qos: .utility)
    private var pendingDirectories: Set<String> = []
    private var debounceWorkItem: DispatchWorkItem?
    private var monitoredDirectories: [URL] = []

    /// Called on the main thread after debounce with the affected root directories.
    var onDirectoriesChanged: ((_ directories: [URL]) -> Void)?

    init(debounceInterval: TimeInterval = Constants.Defaults.fsEventsDebounceSeconds) {
        self.debounceInterval = debounceInterval
    }

    func startMonitoring(directories: [URL]) {
        stopMonitoring()
        guard !directories.isEmpty else { return }

        monitoredDirectories = directories
        let paths = directories.map(\.path) as CFArray

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            fileSystemMonitorCallback,
            &context,
            paths,
            FSEventsGetCurrentEventId(),
            0, // no built-in latency — we debounce ourselves
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        ) else {
            AppLogger.shared.error("FSEvents stream creation failed — monitoring inactive", category: "monitor")
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
        AppLogger.shared.info("FSEvents monitoring started for \(directories.count) paths", category: "monitor")
    }

    func stopMonitoring() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        pendingDirectories.removeAll()

        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    deinit {
        stopMonitoring()
    }

    // MARK: - Internal (called from C callback on queue)

    fileprivate func handleEvents(paths: [String]) {
        // Map each changed path to its monitored root directory
        for path in paths {
            for dir in monitoredDirectories {
                if path.hasPrefix(dir.path) {
                    pendingDirectories.insert(dir.path)
                    break
                }
            }
        }

        // Reset the debounce timer
        debounceWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            guard let self, !self.pendingDirectories.isEmpty else { return }
            let dirs = self.pendingDirectories.map { URL(fileURLWithPath: $0) }
            self.pendingDirectories.removeAll()

            AppLogger.shared.info("FSEvents triggered incremental scan", category: "monitor")

            DispatchQueue.main.async { [weak self] in
                self?.onDirectoriesChanged?(dirs)
            }
        }

        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}

// MARK: - FSEvents C callback

private func fileSystemMonitorCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let monitor = Unmanaged<FileSystemMonitor>.fromOpaque(info).takeUnretainedValue()

    guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }

    monitor.handleEvents(paths: paths)
}
