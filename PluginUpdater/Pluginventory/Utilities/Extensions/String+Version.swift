import Foundation

extension String {
    /// Normalizes a version string by stripping common prefixes like "v", "V", "Version".
    /// Examples: "V2.1.2" -> "2.1.2", "version 1.0" -> "1.0", "build-3.2.1" -> "3.2.1"
    var normalizedVersion: String {
        var s = trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["version", "ver", "v"]
        for prefix in prefixes {
            if s.lowercased().hasPrefix(prefix) {
                s = String(s.dropFirst(prefix.count))
                s = s.trimmingCharacters(in: .whitespacesAndNewlines)
                // Remove leading punctuation like "." or "-" after prefix
                if let first = s.first, first == "." || first == "-" || first == " " {
                    s = String(s.dropFirst())
                }
                break
            }
        }
        return s
    }

    /// Parses a version string into numeric components for comparison.
    /// "2.1.3" -> [2, 1, 3], "1.0" -> [1, 0], "35b2" -> [35], "abc" -> []
    /// Extracts leading digits from each dot-separated segment.
    var versionComponents: [Int] {
        normalizedVersion
            .split(separator: ".")
            .compactMap { segment -> Int? in
                let digits = segment.prefix(while: { $0.isNumber })
                return digits.isEmpty ? nil : Int(digits)
            }
    }

    /// Compares two version strings using semantic versioning rules.
    /// Returns: .orderedAscending if self < other, .orderedSame if equal, .orderedDescending if self > other
    func compareVersion(to other: String) -> ComparisonResult {
        let lhs = self.versionComponents
        let rhs = other.versionComponents
        let maxLength = max(lhs.count, rhs.count)

        for i in 0..<maxLength {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    /// Returns true if this version string represents a newer version than `other`.
    func isNewerVersion(than other: String) -> Bool {
        compareVersion(to: other) == .orderedDescending
    }

    /// Escapes a string for use in a CSV field (wraps in quotes if needed).
    var csvEscaped: String {
        if contains(",") || contains("\"") || contains("\n") {
            return "\"\(replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return self
    }
}
