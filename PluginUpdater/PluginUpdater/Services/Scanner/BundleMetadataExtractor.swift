import Foundation

struct PluginMetadata: Sendable {
    let url: URL
    let format: PluginFormat
    let name: String
    let bundleIdentifier: String
    let version: String
    let vendorName: String

    // Raw plist values for vendor resolution
    let audioComponentName: String?
    let copyright: String?
    let getInfoString: String?
    let bundleIDDomain: String?
    let parentDirectory: String

    /// All string-valued plist fields (for URL extraction by VendorURLResolver)
    let plistFields: [String: String]

    let architectures: [CPUArchitecture]
    let fileSize: Int64
    let fileCreationDate: Date?
}

enum BundleMetadataExtractor {
    enum ExtractionError: Error {
        case noPlist(URL)
        case noBundleIdentifier(URL)
    }

    static func extract(from bundleURL: URL) throws -> PluginMetadata {
        guard let format = bundleURL.pluginFormat else {
            throw ExtractionError.noPlist(bundleURL)
        }

        let plistURL = bundleURL.infoPlistURL
        guard let plist = NSDictionary(contentsOf: plistURL) else {
            throw ExtractionError.noPlist(bundleURL)
        }

        guard let bundleID = plist["CFBundleIdentifier"] as? String, !bundleID.isEmpty else {
            throw ExtractionError.noBundleIdentifier(bundleURL)
        }

        let name = extractName(from: plist, bundleURL: bundleURL)
        let version = extractVersion(from: plist)
        let copyright = plist["NSHumanReadableCopyright"] as? String
        let getInfoString = plist["CFBundleGetInfoString"] as? String
        let audioComponentName = extractAudioComponentName(from: plist)
        let bundleIDDomain = extractDomainFromBundleID(bundleID)
        let parentDir = bundleURL.parentDirectoryName

        let vendorName = VendorResolver.resolve(
            audioComponentName: audioComponentName,
            copyright: copyright,
            getInfoString: getInfoString,
            bundleIDDomain: bundleIDDomain,
            parentDirectory: parentDir,
            format: format
        )

        // Collect all string-valued plist entries for URL extraction
        var fields: [String: String] = [:]
        for (key, value) in plist {
            if let k = key as? String, let v = value as? String {
                fields[k] = v
            }
        }

        // Architecture detection from Mach-O binary
        let executableName = plist["CFBundleExecutable"] as? String
        let architectures = ArchitectureDetector.detect(bundleURL: bundleURL, executableName: executableName)

        // Bundle size: sum all files in the bundle
        let fileSize = Self.calculateBundleSize(bundleURL)

        // File creation date
        let fileCreationDate = Self.getCreationDate(bundleURL)

        return PluginMetadata(
            url: bundleURL,
            format: format,
            name: name,
            bundleIdentifier: bundleID,
            version: version,
            vendorName: vendorName,
            audioComponentName: audioComponentName,
            copyright: copyright,
            getInfoString: getInfoString,
            bundleIDDomain: bundleIDDomain,
            parentDirectory: parentDir,
            plistFields: fields,
            architectures: architectures,
            fileSize: fileSize,
            fileCreationDate: fileCreationDate
        )
    }

    private static func extractName(from plist: NSDictionary, bundleURL: URL) -> String {
        // Prefer display name, fall back to bundle name, then filename
        if let displayName = plist["CFBundleDisplayName"] as? String, !displayName.isEmpty {
            return displayName
        }
        if let bundleName = plist["CFBundleName"] as? String, !bundleName.isEmpty {
            return bundleName
        }
        // Strip extension from filename
        return bundleURL.deletingPathExtension().lastPathComponent
    }

    private static func extractVersion(from plist: NSDictionary) -> String {
        // Prefer short version string, fall back to bundle version
        if let shortVersion = plist["CFBundleShortVersionString"] as? String, !shortVersion.isEmpty {
            return shortVersion.normalizedVersion
        }
        if let bundleVersion = plist["CFBundleVersion"] as? String, !bundleVersion.isEmpty {
            return bundleVersion.normalizedVersion
        }
        return "0.0.0"
    }

    private static func extractAudioComponentName(from plist: NSDictionary) -> String? {
        // AU plugins store manufacturer info in AudioComponents array
        guard let components = plist["AudioComponents"] as? [[String: Any]],
              let first = components.first else {
            return nil
        }

        // Prefer the "name" field which follows "Vendor: PluginName" convention
        if let name = first["name"] as? String,
           let colonRange = name.range(of: ":") {
            let vendor = name[name.startIndex..<colonRange.lowerBound]
                .trimmingCharacters(in: .whitespaces)
            if !vendor.isEmpty {
                return vendor
            }
        }

        // Fall back to manufacturer, but skip short codes (e.g., "oDin", "appl")
        if let manufacturer = first["manufacturer"] as? String, manufacturer.count > 4 {
            return manufacturer
        }

        return nil
    }

    private static func extractDomainFromBundleID(_ bundleID: String) -> String? {
        // "com.fabfilter.ProQ3" -> "fabfilter"
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    /// Calculates the total size of all files in a bundle directory.
    private static func calculateBundleSize(_ bundleURL: URL) -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Gets the filesystem creation date of a bundle.
    private static func getCreationDate(_ bundleURL: URL) -> Date? {
        try? bundleURL.resourceValues(forKeys: [.creationDateKey]).creationDate
    }
}
