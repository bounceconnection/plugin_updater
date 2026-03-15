import Foundation

enum VendorResolver {
    /// Resolves vendor name using a priority chain of heuristics.
    /// Priority: AU manufacturer code > copyright > getInfoString > bundle ID domain > parent directory
    static func resolve(
        audioComponentName: String?,
        copyright: String?,
        getInfoString: String?,
        bundleIDDomain: String?,
        parentDirectory: String,
        format: PluginFormat
    ) -> String {
        // 1. AU AudioComponents manufacturer (most reliable for AU plugins)
        if let manufacturer = audioComponentName, !manufacturer.isEmpty {
            let cleaned = cleanVendorString(manufacturer)
            if !cleaned.isEmpty { return cleaned }
        }

        // 2. NSHumanReadableCopyright - extract company name
        if let copyright = copyright {
            if let extracted = extractVendorFromCopyright(copyright) {
                return extracted
            }
        }

        // 3. CFBundleGetInfoString - often contains vendor info
        if let info = getInfoString {
            if let extracted = extractVendorFromCopyright(info) {
                return extracted
            }
        }

        // 4. Bundle ID domain (e.g., "com.fabfilter.ProQ3" -> "FabFilter")
        if let domain = bundleIDDomain {
            let cleaned = cleanVendorString(domain)
            if !cleaned.isEmpty && !isGenericDomain(cleaned) {
                return capitalizeVendor(cleaned)
            }
        }

        // 5. Parent directory name (e.g., /VST3/Eventide/Plugin.vst3 -> "Eventide")
        let knownPluginDirs = ["VST3", "Components", "CLAP"]
        if !knownPluginDirs.contains(parentDirectory) && !parentDirectory.isEmpty {
            return parentDirectory
        }

        return "Unknown"
    }

    /// Extracts a vendor/company name from a copyright string.
    /// Handles patterns like "Copyright 2024 FabFilter", "(c) Xfer Records", "2024 Native Instruments GmbH"
    static func extractVendorFromCopyright(_ text: String) -> String? {
        var s = text

        // Remove common copyright symbols and prefixes
        let prefixes = ["copyright", "©", "(c)", "copr.", "copr"]
        for prefix in prefixes {
            if let range = s.range(of: prefix, options: .caseInsensitive) {
                s = String(s[range.upperBound...])
            }
        }

        s = s.trimmingCharacters(in: .whitespacesAndNewlines)

        // Remove leading year patterns like "2024 " or "2024, "
        if let match = s.range(of: #"^\d{4}[\s,\-]*"#, options: .regularExpression) {
            s = String(s[match.upperBound...])
        }

        // Remove trailing year patterns like " 2024" or ", 2021"
        if let match = s.range(of: #"[\s,\-]+\d{4}$"#, options: .regularExpression) {
            s = String(s[..<match.lowerBound])
        }

        // Remove trailing "All Rights Reserved" and similar
        let suffixes = ["all rights reserved", "all rights reserved.", "inc.", "inc", "llc.", "llc", "ltd.", "ltd", "gmbh"]
        for suffix in suffixes {
            if s.lowercased().hasSuffix(suffix) {
                s = String(s.dropLast(suffix.count))
            }
        }

        s = s.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".,;-")))

        guard !s.isEmpty else { return nil }

        // Reject version-number-like strings (e.g., "2.0.3", "1.0")
        if s.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) { return nil }

        return s
    }

    private static func cleanVendorString(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".,;-")))
    }

    private static func isGenericDomain(_ domain: String) -> Bool {
        let generic = ["apple", "mac", "audio", "music", "plugin", "plugins", "app", "software"]
        return generic.contains(domain.lowercased())
    }

    private static func capitalizeVendor(_ s: String) -> String {
        // Simple capitalization: "fabfilter" -> "Fabfilter"
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
}
