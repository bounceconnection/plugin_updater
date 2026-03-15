import Foundation
import SwiftData

@Model
final class Plugin {
    var name: String
    var bundleIdentifier: String
    var format: PluginFormat
    var currentVersion: String
    var path: String
    var vendorName: String
    var installedDate: Date
    var lastSeenDate: Date
    var isRemoved: Bool
    var isHidden: Bool = false
    /// Comma-separated architecture raw values (e.g. "arm64,x86_64").
    var architecturesRaw: String = ""
    var fileSize: Int64 = 0
    var fileCreationDate: Date?

    @Relationship(deleteRule: .cascade, inverse: \PluginVersion.plugin)
    var versionHistory: [PluginVersion]

    @Relationship(inverse: \VendorInfo.plugins)
    var vendor: VendorInfo?

    init(
        name: String,
        bundleIdentifier: String,
        format: PluginFormat,
        currentVersion: String,
        path: String,
        vendorName: String = "Unknown",
        installedDate: Date = .now,
        lastSeenDate: Date = .now,
        isRemoved: Bool = false,
        isHidden: Bool = false
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.format = format
        self.currentVersion = currentVersion
        self.path = path
        self.vendorName = vendorName
        self.installedDate = installedDate
        self.lastSeenDate = lastSeenDate
        self.isRemoved = isRemoved
        self.isHidden = isHidden
        self.versionHistory = []
    }

    var pathURL: URL {
        URL(fileURLWithPath: path)
    }

    /// Parsed CPU architectures from the raw string.
    var architectures: [CPUArchitecture] {
        get {
            guard !architecturesRaw.isEmpty else { return [] }
            return architecturesRaw.split(separator: ",").compactMap { CPUArchitecture(rawValue: String($0)) }
        }
        set {
            architecturesRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    /// Human-readable architecture display string.
    var architectureDisplayString: String {
        architectures.displayString
    }

    /// Whether the plugin uses a legacy architecture (i386, PPC).
    var isLegacyArchitecture: Bool {
        architectures.isLegacy
    }
}
