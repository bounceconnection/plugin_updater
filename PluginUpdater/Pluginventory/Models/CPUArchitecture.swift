import Foundation

/// CPU architecture detected from a plugin's Mach-O binary.
enum CPUArchitecture: String, Codable, Sendable {
    case arm64
    case x86_64
    case i386
    case ppc
    case unknown
}

extension Array where Element == CPUArchitecture {
    /// Human-readable display string for a set of architectures.
    var displayString: String {
        let known = filter { $0 != .unknown }
        guard !known.isEmpty else { return "Unknown" }

        let hasARM = known.contains(.arm64)
        let hasX64 = known.contains(.x86_64)
        let hasI386 = known.contains(.i386)
        let hasPPC = known.contains(.ppc)

        if hasARM && hasX64 { return "Universal" }
        if hasARM { return "Apple Silicon" }
        if hasX64 { return "Intel 64" }
        if hasI386 { return "Intel 32" }
        if hasPPC { return "PowerPC" }

        return "Unknown"
    }

    /// Whether any architecture in the list is considered legacy (may not run natively).
    var isLegacy: Bool {
        contains(.i386) || contains(.ppc)
    }
}
