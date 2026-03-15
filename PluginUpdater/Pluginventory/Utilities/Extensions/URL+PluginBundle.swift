import Foundation

extension URL {
    var isPluginBundle: Bool {
        let ext = pathExtension.lowercased()
        return ext == "vst3" || ext == "component" || ext == "clap" || ext == "vst"
    }

    var pluginFormat: PluginFormat? {
        switch pathExtension.lowercased() {
        case "vst3": return .vst3
        case "component": return .au
        case "clap": return .clap
        case "vst": return .vst2
        default: return nil
        }
    }

    var infoPlistURL: URL {
        appendingPathComponent("Contents/Info.plist")
    }

    var parentDirectoryName: String {
        deletingLastPathComponent().lastPathComponent
    }
}
