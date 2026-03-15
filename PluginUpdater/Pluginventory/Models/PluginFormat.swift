import Foundation

enum PluginFormat: String, Codable, CaseIterable, Identifiable {
    case au
    case clap
    case vst2
    case vst3

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .au: "AU"
        case .clap: "CLAP"
        case .vst2: "VST2"
        case .vst3: "VST3"
        }
    }

    var fileExtension: String {
        switch self {
        case .au: "component"
        case .clap: "clap"
        case .vst2: "vst"
        case .vst3: "vst3"
        }
    }

    var systemDirectory: URL {
        switch self {
        case .au:
            URL(fileURLWithPath: "/Library/Audio/Plug-Ins/Components")
        case .clap:
            URL(fileURLWithPath: "/Library/Audio/Plug-Ins/CLAP")
        case .vst2:
            URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST")
        case .vst3:
            URL(fileURLWithPath: "/Library/Audio/Plug-Ins/VST3")
        }
    }

}
