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
        isInstalled: Bool = false
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
    }
}
