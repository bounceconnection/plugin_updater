import Foundation

enum PluginFormat: String, Codable, CaseIterable, Identifiable {
    case vst3
    case au
    case clap

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .vst3: "VST3"
        case .au: "AU"
        case .clap: "CLAP"
        }
    }

    var fileExtension: String {
        switch self {
        case .vst3: "vst3"
        case .au: "component"
        case .clap: "clap"
        }
    }

    var systemDirectory: URL {
        switch self {
        case .vst3:
            URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3")
        case .au:
            URL(fileURLWithPath: "/Library/Audio/Plug-Ins/Components")
        case .clap:
            URL(fileURLWithPath: "/Library/Audio/Plug-Ins/CLAP")
        }
    }

    var userDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .vst3:
            return home.appendingPathComponent("Library/Audio/Plug-Ins/VST3")
        case .au:
            return home.appendingPathComponent("Library/Audio/Plug-Ins/Components")
        case .clap:
            return home.appendingPathComponent("Library/Audio/Plug-Ins/CLAP")
        }
    }

    var allDirectories: [URL] {
        [systemDirectory, userDirectory]
    }
}
