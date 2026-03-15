import Foundation
import zlib

/// Parses Ableton Live .als files (gzip-compressed XML) to extract plugin references.
actor AbletonProjectParser {

    struct ParsedProject: Sendable {
        let name: String
        let filePath: String
        let lastModified: Date
        let fileSize: Int64
        let abletonVersion: String?
        let plugins: [ParsedPlugin]
    }

    struct ParsedPlugin: Sendable, Hashable {
        let pluginName: String
        let pluginType: String
        let auComponentType: String?
        let auComponentSubType: String?
        let auComponentManufacturer: String?
        let vst3TUID: String?
        let vendorName: String?

        func hash(into hasher: inout Hasher) {
            hasher.combine(pluginType)
            switch pluginType {
            case "au":
                hasher.combine(auComponentSubType)
                hasher.combine(auComponentManufacturer)
            case "vst3":
                hasher.combine(vst3TUID)
            default:
                hasher.combine(pluginName.lowercased())
            }
        }

        static func == (lhs: ParsedPlugin, rhs: ParsedPlugin) -> Bool {
            if lhs.pluginType != rhs.pluginType { return false }
            switch lhs.pluginType {
            case "au":
                return lhs.auComponentSubType == rhs.auComponentSubType &&
                       lhs.auComponentManufacturer == rhs.auComponentManufacturer
            case "vst3":
                return lhs.vst3TUID == rhs.vst3TUID
            default:
                return lhs.pluginName.lowercased() == rhs.pluginName.lowercased()
            }
        }
    }

    enum ParseError: Error {
        case fileNotFound(URL)
        case decompressFailed(URL)
        case xmlParseFailed(URL, String)
    }

    func parse(fileURL: URL) throws -> ParsedProject {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            throw ParseError.fileNotFound(fileURL)
        }

        let attrs = try fm.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attrs[.size] as? Int64) ?? 0
        let lastModified = (attrs[.modificationDate] as? Date) ?? .now

        let compressedData = try Data(contentsOf: fileURL)
        guard let xmlData = decompressGzip(compressedData) else {
            throw ParseError.decompressFailed(fileURL)
        }

        let delegate = ALSXMLDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate

        guard parser.parse() else {
            let errorMsg = parser.parserError?.localizedDescription ?? "Unknown parse error"
            throw ParseError.xmlParseFailed(fileURL, errorMsg)
        }

        let uniquePlugins = Array(Set(delegate.plugins))
        let projectName = fileURL.deletingPathExtension().lastPathComponent

        if AppLogger.shared.verbose {
            AppLogger.shared.info(
                "Parsed \(projectName): \(uniquePlugins.count) plugins (from \(delegate.plugins.count) raw)",
                category: "projectScan"
            )
        }

        return ParsedProject(
            name: projectName,
            filePath: fileURL.path,
            lastModified: lastModified,
            fileSize: fileSize,
            abletonVersion: delegate.abletonVersion,
            plugins: uniquePlugins
        )
    }

    // MARK: - Gzip Decompression

    private func decompressGzip(_ data: Data) -> Data? {
        guard data.count >= 2, data[0] == 0x1f, data[1] == 0x8b else {
            return data // Not gzip — return as-is (plain XML)
        }

        var stream = z_stream()
        // windowBits = 15 + 32 tells zlib to auto-detect gzip/zlib headers
        guard inflateInit2_(&stream, 15 + 32, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { inflateEnd(&stream) }

        var output = Data(capacity: data.count * 4)

        return data.withUnsafeBytes { inputPtr -> Data? in
            guard let baseAddress = inputPtr.baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer(mutating: baseAddress.assumingMemoryBound(to: UInt8.self))
            stream.avail_in = UInt32(data.count)

            let chunkSize = 65_536
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
            defer { buffer.deallocate() }

            repeat {
                stream.next_out = buffer
                stream.avail_out = UInt32(chunkSize)

                let status = inflate(&stream, Z_NO_FLUSH)
                guard status == Z_OK || status == Z_STREAM_END else { return nil }

                let bytesWritten = chunkSize - Int(stream.avail_out)
                output.append(buffer, count: bytesWritten)

                if status == Z_STREAM_END { break }
            } while stream.avail_out == 0

            return output
        }
    }
}

// MARK: - SAX XML Delegate

private final class ALSXMLDelegate: NSObject, XMLParserDelegate {
    var abletonVersion: String?
    var plugins: [AbletonProjectParser.ParsedPlugin] = []

    private var elementStack: [String] = []

    // AU plugin state
    private var inAuPluginInfo = false
    private var auPluginInfoDepth = 0
    private var auName: String?
    private var auManufacturer: String?
    private var auComponentType: String?
    private var auComponentSubType: String?
    private var auComponentManufacturer: String?

    // VST3 plugin state
    private var inVst3PluginInfo = false
    private var vst3PluginInfoDepth = 0
    private var vst3Name: String?
    private var vst3UidFields: [String: String] = [:]

    // VST2 plugin state
    private var inVstPluginInfo = false
    private var vst2PlugName: String?

    // Context for VST3 name resolution
    private var lastBranchPresetName: String?
    private var currentPluginDeviceName: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        elementStack.append(elementName)

        // Root element has Ableton version
        if elementName == "Ableton" {
            abletonVersion = attributes["Creator"]
        }

        // Track PluginDevice UserName for VST3 name resolution
        if elementName == "PluginDevice" {
            currentPluginDeviceName = nil
        }
        if elementName == "UserName" && elementStack.dropLast().last == "PluginDevice" {
            currentPluginDeviceName = attributes["Value"]
        }

        // AU Plugin — track nesting depth to distinguish direct children
        // from elements inside nested <Preset><AuPreset> blocks
        if elementName == "AuPluginInfo" {
            inAuPluginInfo = true
            auPluginInfoDepth = elementStack.count
            auName = nil; auManufacturer = nil
            auComponentType = nil; auComponentSubType = nil; auComponentManufacturer = nil
        }
        if inAuPluginInfo {
            let depthInBlock = elementStack.count - auPluginInfoDepth
            // Only capture direct children of AuPluginInfo (depth 1)
            if depthInBlock == 1 {
                if elementName == "Name" { auName = attributes["Value"] }
                if elementName == "Manufacturer" { auManufacturer = attributes["Value"] }
                if elementName == "ComponentType" {
                    if let v = attributes["Value"], let num = UInt32(v) {
                        auComponentType = fourCharCode(from: num)
                    }
                }
                if elementName == "ComponentSubType" {
                    if let v = attributes["Value"], let num = UInt32(v) {
                        auComponentSubType = fourCharCode(from: num)
                    }
                }
                if elementName == "ComponentManufacturer" {
                    if let v = attributes["Value"], let num = UInt32(v) {
                        auComponentManufacturer = fourCharCode(from: num)
                    }
                }
            }
        }

        // VST3 Plugin — track nesting depth to distinguish direct children
        // from elements inside nested <Preset><Vst3Preset> blocks
        if elementName == "Vst3PluginInfo" {
            inVst3PluginInfo = true
            vst3PluginInfoDepth = elementStack.count
            vst3Name = nil
            vst3UidFields = [:]
        }
        if inVst3PluginInfo {
            let depthInBlock = elementStack.count - vst3PluginInfoDepth
            // Direct children of Vst3PluginInfo are at depth 1
            if elementName == "Name" && depthInBlock == 1 {
                vst3Name = attributes["Value"]
            }
            // Uid/Fields at depth 1-2 (Uid is depth 1, Fields.N is depth 2)
            if elementName.hasPrefix("Fields.") && depthInBlock == 2 {
                // Only capture if parent is Uid directly under Vst3PluginInfo
                if elementStack.dropLast().last == "Uid" {
                    vst3UidFields[elementName] = attributes["Value"]
                }
            }
        }

        // VST2 Plugin
        if elementName == "VstPluginInfo" {
            inVstPluginInfo = true
            vst2PlugName = nil
        }
        if inVstPluginInfo && elementName == "PlugName" {
            vst2PlugName = attributes["Value"]
        }

        // Track BranchPresetName for VST3 name resolution
        if elementName == "BranchPresetName" {
            lastBranchPresetName = attributes["Value"]
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        if elementName == "AuPluginInfo" && inAuPluginInfo {
            inAuPluginInfo = false
            if let name = auName, !name.isEmpty {
                plugins.append(AbletonProjectParser.ParsedPlugin(
                    pluginName: name,
                    pluginType: "au",
                    auComponentType: auComponentType,
                    auComponentSubType: auComponentSubType,
                    auComponentManufacturer: auComponentManufacturer,
                    vst3TUID: nil,
                    vendorName: auManufacturer
                ))
            }
        }

        if elementName == "Vst3PluginInfo" && inVst3PluginInfo {
            inVst3PluginInfo = false
            let tuid = buildVST3TUID(from: vst3UidFields)
            let resolvedName = vst3Name
                ?? currentPluginDeviceName
                ?? lastBranchPresetName
                ?? "Unknown VST3"
            if !resolvedName.isEmpty && !vst3UidFields.isEmpty {
                plugins.append(AbletonProjectParser.ParsedPlugin(
                    pluginName: resolvedName,
                    pluginType: "vst3",
                    auComponentType: nil,
                    auComponentSubType: nil,
                    auComponentManufacturer: nil,
                    vst3TUID: tuid,
                    vendorName: nil
                ))
            }
            lastBranchPresetName = nil
            currentPluginDeviceName = nil
        }

        if elementName == "VstPluginInfo" && inVstPluginInfo {
            inVstPluginInfo = false
            if let name = vst2PlugName, !name.isEmpty {
                plugins.append(AbletonProjectParser.ParsedPlugin(
                    pluginName: name,
                    pluginType: "vst2",
                    auComponentType: nil,
                    auComponentSubType: nil,
                    auComponentManufacturer: nil,
                    vst3TUID: nil,
                    vendorName: nil
                ))
            }
        }

        _ = elementStack.popLast()
    }

    // MARK: - Helpers

    private func fourCharCode(from value: UInt32) -> String {
        let bytes = withUnsafeBytes(of: value.bigEndian) { Array($0) }
        return String(bytes.compactMap {
            $0 >= 0x20 && $0 <= 0x7E ? Character(UnicodeScalar($0)) : nil
        })
    }

    private func buildVST3TUID(from fields: [String: String]) -> String? {
        guard let f0 = fields["Fields.0"], let v0 = parseUInt32(f0),
              let f1 = fields["Fields.1"], let v1 = parseUInt32(f1),
              let f2 = fields["Fields.2"], let v2 = parseUInt32(f2),
              let f3 = fields["Fields.3"], let v3 = parseUInt32(f3) else {
            return nil
        }
        return String(format: "%08X%08X%08X%08X", v0, v1, v2, v3)
    }

    /// Parses a string that may be a signed or unsigned 32-bit integer.
    /// Ableton .als files store TUID fields as signed Int32 values (can be negative).
    private func parseUInt32(_ string: String) -> UInt32? {
        if let unsigned = UInt32(string) {
            return unsigned
        }
        if let signed = Int32(string) {
            return UInt32(bitPattern: signed)
        }
        return nil
    }
}
