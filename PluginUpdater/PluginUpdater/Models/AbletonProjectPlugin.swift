import Foundation
import SwiftData

@Model
final class AbletonProjectPlugin {
    var pluginName: String
    var pluginType: String
    var auComponentType: String?
    var auComponentSubType: String?
    var auComponentManufacturer: String?
    var vst3TUID: String?
    var vendorName: String?
    var matchedPluginID: String?
    var isInstalled: Bool = false
    /// How many times this plugin appears across tracks in the parent project.
    var instanceCount: Int = 1
    var project: AbletonProject?

    init(
        pluginName: String,
        pluginType: String,
        auComponentType: String? = nil,
        auComponentSubType: String? = nil,
        auComponentManufacturer: String? = nil,
        vst3TUID: String? = nil,
        vendorName: String? = nil,
        matchedPluginID: String? = nil,
        isInstalled: Bool = false,
        instanceCount: Int = 1
    ) {
        self.pluginName = pluginName
        self.pluginType = pluginType
        self.auComponentType = auComponentType
        self.auComponentSubType = auComponentSubType
        self.auComponentManufacturer = auComponentManufacturer
        self.vst3TUID = vst3TUID
        self.vendorName = vendorName
        self.matchedPluginID = matchedPluginID
        self.isInstalled = isInstalled
        self.instanceCount = instanceCount
    }
}
