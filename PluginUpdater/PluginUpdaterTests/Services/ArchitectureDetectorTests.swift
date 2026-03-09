import Testing
import Foundation
@testable import PluginUpdater

@Suite("ArchitectureDetector Tests")
struct ArchitectureDetectorTests {

    /// Creates a temporary mock plugin bundle with a fake executable binary.
    private func createMockBundle(
        name: String,
        executableName: String? = nil,
        binaryData: Data
    ) throws -> (bundleURL: URL, execName: String?) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ArchDetectorTests-\(UUID().uuidString)")
        let bundleURL = tempDir.appendingPathComponent("\(name).vst3")
        let execName = executableName ?? name
        let macosDir = bundleURL.appendingPathComponent("Contents/MacOS")

        try FileManager.default.createDirectory(at: macosDir, withIntermediateDirectories: true)

        let execURL = macosDir.appendingPathComponent(execName)
        try binaryData.write(to: execURL)

        return (bundleURL, executableName)
    }

    private func cleanup(_ url: URL) {
        // Remove the temp directory (parent of the bundle)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - Fat binary helpers

    /// Builds a minimal fat binary header with the given CPU types (big-endian format).
    private func makeFatBinary(cpuTypes: [UInt32]) -> Data {
        var data = Data()
        // Fat magic (big-endian): 0xCAFEBABE
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0xCAFE_BABE).bigEndian) { Array($0) })
        // Number of architectures (big-endian)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(cpuTypes.count).bigEndian) { Array($0) })
        // Fat arch entries: cputype(4) + cpusubtype(4) + offset(4) + size(4) + align(4) = 20 bytes each
        for cpuType in cpuTypes {
            data.append(contentsOf: withUnsafeBytes(of: cpuType.bigEndian) { Array($0) }) // cputype
            data.append(contentsOf: [0, 0, 0, 0]) // cpusubtype
            data.append(contentsOf: [0, 0, 0, 0]) // offset
            data.append(contentsOf: [0, 0, 0, 0]) // size
            data.append(contentsOf: [0, 0, 0, 0]) // align
        }
        return data
    }

    /// Builds a minimal single-arch Mach-O header (native endian).
    private func makeMachO64(cpuType: UInt32) -> Data {
        var data = Data()
        // Mach-O 64 magic: 0xFEEDFACF
        var magic: UInt32 = 0xFEED_FACF
        data.append(contentsOf: withUnsafeBytes(of: &magic) { Array($0) })
        // CPU type
        var cpu = cpuType
        data.append(contentsOf: withUnsafeBytes(of: &cpu) { Array($0) })
        return data
    }

    // MARK: - Tests

    @Test("Detects Universal (ARM64 + x86_64) from fat binary")
    func detectsUniversal() throws {
        let data = makeFatBinary(cpuTypes: [0x0100_000C, 0x0100_0007]) // arm64, x86_64
        let (bundleURL, execName) = try createMockBundle(name: "UniversalPlugin", binaryData: data)
        defer { cleanup(bundleURL) }

        let archs = ArchitectureDetector.detect(bundleURL: bundleURL, executableName: execName)
        #expect(archs.contains(.arm64))
        #expect(archs.contains(.x86_64))
        #expect(archs.count == 2)
        #expect(archs.displayString == "Universal")
        #expect(!archs.isLegacy)
    }

    @Test("Detects Apple Silicon from single-arch Mach-O")
    func detectsAppleSilicon() throws {
        let data = makeMachO64(cpuType: 0x0100_000C) // arm64
        let (bundleURL, execName) = try createMockBundle(name: "ARMPlugin", binaryData: data)
        defer { cleanup(bundleURL) }

        let archs = ArchitectureDetector.detect(bundleURL: bundleURL, executableName: execName)
        #expect(archs == [.arm64])
        #expect(archs.displayString == "Apple Silicon")
    }

    @Test("Detects Intel 64 from single-arch Mach-O")
    func detectsIntel64() throws {
        let data = makeMachO64(cpuType: 0x0100_0007) // x86_64
        let (bundleURL, execName) = try createMockBundle(name: "IntelPlugin", binaryData: data)
        defer { cleanup(bundleURL) }

        let archs = ArchitectureDetector.detect(bundleURL: bundleURL, executableName: execName)
        #expect(archs == [.x86_64])
        #expect(archs.displayString == "Intel 64")
    }

    @Test("Flags Intel 32-bit as legacy")
    func flagsI386AsLegacy() throws {
        let data = makeFatBinary(cpuTypes: [0x0000_0007]) // i386
        let (bundleURL, execName) = try createMockBundle(name: "I386Plugin", binaryData: data)
        defer { cleanup(bundleURL) }

        let archs = ArchitectureDetector.detect(bundleURL: bundleURL, executableName: execName)
        #expect(archs == [.i386])
        #expect(archs.displayString == "Intel 32")
        #expect(archs.isLegacy)
    }

    @Test("Flags PowerPC as legacy")
    func flagsPPCAsLegacy() throws {
        let data = makeFatBinary(cpuTypes: [0x0000_0012]) // ppc
        let (bundleURL, execName) = try createMockBundle(name: "PPCPlugin", binaryData: data)
        defer { cleanup(bundleURL) }

        let archs = ArchitectureDetector.detect(bundleURL: bundleURL, executableName: execName)
        #expect(archs == [.ppc])
        #expect(archs.displayString == "PowerPC")
        #expect(archs.isLegacy)
    }

    @Test("Returns empty array for missing executable")
    func missingExecutable() {
        let fakeURL = URL(fileURLWithPath: "/nonexistent/bundle.vst3")
        let archs = ArchitectureDetector.detect(bundleURL: fakeURL, executableName: "NoSuchBinary")
        #expect(archs.isEmpty)
    }

    @Test("Returns empty array for non-Mach-O file")
    func nonMachOFile() throws {
        let data = Data("This is not a binary".utf8)
        let (bundleURL, execName) = try createMockBundle(name: "TextPlugin", binaryData: data)
        defer { cleanup(bundleURL) }

        let archs = ArchitectureDetector.detect(bundleURL: bundleURL, executableName: execName)
        #expect(archs.isEmpty)
    }

    @Test("Falls back to bundle name when executableName is nil")
    func fallsBackToBundleName() throws {
        let data = makeMachO64(cpuType: 0x0100_000C) // arm64
        let (bundleURL, _) = try createMockBundle(name: "FallbackPlugin", binaryData: data)
        defer { cleanup(bundleURL) }

        let archs = ArchitectureDetector.detect(bundleURL: bundleURL, executableName: nil)
        #expect(archs == [.arm64])
    }

    // MARK: - Display string tests

    @Test("Display string mappings are correct")
    func displayStringMappings() {
        #expect([CPUArchitecture.arm64, .x86_64].displayString == "Universal")
        #expect([CPUArchitecture.arm64].displayString == "Apple Silicon")
        #expect([CPUArchitecture.x86_64].displayString == "Intel 64")
        #expect([CPUArchitecture.i386].displayString == "Intel 32")
        #expect([CPUArchitecture.ppc].displayString == "PowerPC")
        #expect([CPUArchitecture.unknown].displayString == "Unknown")
        #expect([CPUArchitecture]().displayString == "Unknown")
    }
}
