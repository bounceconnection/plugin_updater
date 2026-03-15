import Foundation
import SwiftData

@Model
final class VendorInfo {
    var name: String
    var websiteURL: String?
    var supportURL: String?

    var plugins: [Plugin]

    init(
        name: String,
        websiteURL: String? = nil,
        supportURL: String? = nil
    ) {
        self.name = name
        self.websiteURL = websiteURL
        self.supportURL = supportURL
        self.plugins = []
    }

    var pluginCount: Int {
        plugins.count
    }
}
