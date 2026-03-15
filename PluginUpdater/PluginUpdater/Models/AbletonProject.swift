import Foundation
import SwiftData

@Model
final class AbletonProject {
    @Attribute(.unique) var filePath: String
    var name: String
    var lastModified: Date
    var fileSize: Int64
    var abletonVersion: String?
    @Relationship(deleteRule: .cascade, inverse: \AbletonProjectPlugin.project)
    var plugins: [AbletonProjectPlugin] = []
    var isRemoved: Bool = false
    var lastScannedDate: Date?

    init(
        filePath: String,
        name: String,
        lastModified: Date,
        fileSize: Int64,
        abletonVersion: String? = nil,
        isRemoved: Bool = false,
        lastScannedDate: Date? = nil
    ) {
        self.filePath = filePath
        self.name = name
        self.lastModified = lastModified
        self.fileSize = fileSize
        self.abletonVersion = abletonVersion
        self.isRemoved = isRemoved
        self.lastScannedDate = lastScannedDate
        self.plugins = []
    }

    var fileURL: URL {
        URL(fileURLWithPath: filePath)
    }

    var installedPluginCount: Int {
        plugins.filter(\.isInstalled).count
    }

    var missingPluginCount: Int {
        plugins.filter { !$0.isInstalled }.count
    }
}
