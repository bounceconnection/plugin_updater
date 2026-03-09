import Foundation

/// Reads Mach-O headers from a plugin bundle's executable to determine CPU architectures.
/// Only reads the first few KB of the binary — no external processes needed.
enum ArchitectureDetector {

    // MARK: - Mach-O constants

    private static let fatMagic: UInt32 = 0xCAFE_BABE         // big-endian fat
    private static let fatMagicSwapped: UInt32 = 0xBEBA_FECA   // little-endian fat
    private static let machO64Magic: UInt32 = 0xFEED_FACF
    private static let machO32Magic: UInt32 = 0xFEED_FACE
    private static let machO64MagicSwapped: UInt32 = 0xCFFA_EDFE
    private static let machO32MagicSwapped: UInt32 = 0xCEFA_EDFE

    // CPU type constants from mach/machine.h
    private static let cpuTypeARM64: UInt32 = 0x0100_000C
    private static let cpuTypeX86_64: UInt32 = 0x0100_0007
    private static let cpuTypeI386: UInt32 = 0x0000_0007
    private static let cpuTypePPC: UInt32 = 0x0000_0012

    // MARK: - Public

    /// Detects CPU architectures from a plugin bundle's main executable.
    /// - Parameters:
    ///   - bundleURL: Path to the .vst3/.component/.clap bundle
    ///   - executableName: Value of CFBundleExecutable from the bundle's Info.plist
    /// - Returns: Array of detected architectures, empty if detection fails.
    static func detect(bundleURL: URL, executableName: String?) -> [CPUArchitecture] {
        guard let execName = executableName, !execName.isEmpty else {
            // Fall back to bundle name without extension
            let fallback = bundleURL.deletingPathExtension().lastPathComponent
            return detect(executableURL: bundleURL.appendingPathComponent("Contents/MacOS/\(fallback)"))
        }
        return detect(executableURL: bundleURL.appendingPathComponent("Contents/MacOS/\(execName)"))
    }

    // MARK: - Private

    private static func detect(executableURL: URL) -> [CPUArchitecture] {
        guard let handle = try? FileHandle(forReadingFrom: executableURL) else {
            return []
        }
        defer { try? handle.close() }

        guard let magicData = try? handle.read(upToCount: 4), magicData.count == 4 else {
            return []
        }
        let magic = magicData.withUnsafeBytes { $0.load(as: UInt32.self) }

        if magic == fatMagic || magic == fatMagicSwapped {
            return parseFatBinary(handle: handle, swapped: magic == fatMagicSwapped)
        } else if magic == machO64Magic || magic == machO64MagicSwapped ||
                  magic == machO32Magic || magic == machO32MagicSwapped {
            let swapped = (magic == machO64MagicSwapped || magic == machO32MagicSwapped)
            return parseSingleArch(handle: handle, swapped: swapped)
        }

        return []
    }

    private static func parseFatBinary(handle: FileHandle, swapped: Bool) -> [CPUArchitecture] {
        // Fat header: magic (4 bytes) + nfat_arch (4 bytes)
        guard let countData = try? handle.read(upToCount: 4), countData.count == 4 else {
            return []
        }
        var nArch = countData.withUnsafeBytes { $0.load(as: UInt32.self) }
        if swapped { nArch = nArch.byteSwapped }

        // Sanity: don't read more than 20 arch entries
        let count = min(Int(nArch), 20)
        var archs: [CPUArchitecture] = []

        for _ in 0..<count {
            // Each fat_arch entry: cputype(4) + cpusubtype(4) + offset(4) + size(4) + align(4) = 20 bytes
            guard let entry = try? handle.read(upToCount: 20), entry.count == 20 else { break }
            var cpuType = entry.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) }
            if swapped { cpuType = cpuType.byteSwapped }
            archs.append(mapCPUType(cpuType))
        }

        return archs
    }

    private static func parseSingleArch(handle: FileHandle, swapped: Bool) -> [CPUArchitecture] {
        // Mach-O header after magic: cputype (4 bytes)
        guard let cpuData = try? handle.read(upToCount: 4), cpuData.count == 4 else {
            return []
        }
        var cpuType = cpuData.withUnsafeBytes { $0.load(as: UInt32.self) }
        if swapped { cpuType = cpuType.byteSwapped }
        return [mapCPUType(cpuType)]
    }

    private static func mapCPUType(_ cpuType: UInt32) -> CPUArchitecture {
        switch cpuType {
        case cpuTypeARM64: return .arm64
        case cpuTypeX86_64: return .x86_64
        case cpuTypeI386: return .i386
        case cpuTypePPC: return .ppc
        default: return .unknown
        }
    }
}
