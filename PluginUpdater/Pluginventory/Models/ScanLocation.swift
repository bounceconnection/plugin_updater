import Foundation
import SwiftData

@Model
final class ScanLocation {
    var path: String
    var format: PluginFormat
    var isDefault: Bool
    var isEnabled: Bool

    init(
        path: String,
        format: PluginFormat,
        isDefault: Bool = false,
        isEnabled: Bool = true
    ) {
        self.path = path
        self.format = format
        self.isDefault = isDefault
        self.isEnabled = isEnabled
    }

    var url: URL {
        if path.hasPrefix("~") {
            let expanded = NSString(string: path).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
        return URL(fileURLWithPath: path)
    }
}
