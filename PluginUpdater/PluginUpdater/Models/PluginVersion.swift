import Foundation
import SwiftData

@Model
final class PluginVersion {
    var version: String
    var detectedDate: Date
    var previousVersion: String?

    var plugin: Plugin?

    init(
        version: String,
        detectedDate: Date = .now,
        previousVersion: String? = nil
    ) {
        self.version = version
        self.detectedDate = detectedDate
        self.previousVersion = previousVersion
    }
}
