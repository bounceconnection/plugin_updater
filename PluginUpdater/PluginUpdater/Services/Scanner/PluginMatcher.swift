import Foundation
import SwiftData

/// Matches plugin references extracted from Ableton projects against installed plugins.
enum PluginMatcher {

    struct MatchResult {
        let matchedPluginID: String?
        let isInstalled: Bool
    }

    /// Pre-built index for O(1) plugin lookups. Build once before a matching loop.
    struct PluginIndex {
        let byFormatAndName: [String: Plugin]
        let byNameLower: [String: [Plugin]]
        let byNormalizedName: [String: Plugin]
        let byVendorLower: [String: [Plugin]]
        let allActive: [Plugin]

        init(plugins: [Plugin]) {
            var formatAndName: [String: Plugin] = [:]
            var nameLower: [String: [Plugin]] = [:]
            var normalized: [String: Plugin] = [:]
            var vendorLower: [String: [Plugin]] = [:]
            var active: [Plugin] = []

            for plugin in plugins where !plugin.isRemoved {
                active.append(plugin)

                let key = "\(plugin.format.rawValue):\(plugin.name.lowercased())"
                formatAndName[key] = plugin

                let lower = plugin.name.lowercased()
                nameLower[lower, default: []].append(plugin)

                let norm = lower.filter { $0.isLetter || $0.isNumber }
                if norm.count >= 3 {
                    normalized[norm] = plugin
                }

                let vendor = plugin.vendorName.lowercased()
                if !vendor.isEmpty {
                    vendorLower[vendor, default: []].append(plugin)
                }
            }

            self.byFormatAndName = formatAndName
            self.byNameLower = nameLower
            self.byNormalizedName = normalized
            self.byVendorLower = vendorLower
            self.allActive = active
        }
    }

    /// Matches a parsed plugin reference using a pre-built index. Preferred for batch matching.
    static func match(
        _ parsed: AbletonProjectParser.ParsedPlugin,
        index: PluginIndex
    ) -> MatchResult {
        let result: MatchResult
        switch parsed.pluginType {
        case "au":
            result = matchAU(parsed, index: index)
        case "vst3":
            result = matchVST3(parsed, index: index)
        case "vst2":
            result = matchVST2(parsed, index: index)
        default:
            result = MatchResult(matchedPluginID: nil, isInstalled: false)
        }

        if !result.isInstalled && AppLogger.shared.verbose {
            AppLogger.shared.info(
                "  UNMATCHED [\(parsed.pluginType)] \"\(parsed.pluginName)\"\(parsed.vendorName.map { " vendor=\($0)" } ?? "")",
                category: "projectScan"
            )
        }

        return result
    }

    /// Backward-compatible overload that builds a temporary index.
    static func match(
        _ parsed: AbletonProjectParser.ParsedPlugin,
        installedPlugins: [Plugin]
    ) -> MatchResult {
        let index = PluginIndex(plugins: installedPlugins)
        return match(parsed, index: index)
    }

    // MARK: - AU Matching

    private static func matchAU(
        _ parsed: AbletonProjectParser.ParsedPlugin,
        index: PluginIndex
    ) -> MatchResult {
        // Format-specific exact match
        let key = "au:\(parsed.pluginName.lowercased())"
        if let match = index.byFormatAndName[key] {
            return MatchResult(matchedPluginID: "\(match.id)", isInstalled: true)
        }

        // Vendor-scoped fuzzy: if vendor matches, try stripped-name substring match
        if let vendor = parsed.vendorName {
            let vendorLower = vendor.lowercased()
            let strippedName = parsed.pluginName.replacingOccurrences(
                of: #"\s*\d+(\.\d+)*$"#,
                with: "",
                options: .regularExpression
            )
            if strippedName != parsed.pluginName {
                if let vendorPlugins = index.byVendorLower[vendorLower] {
                    let auVendorPlugins = vendorPlugins.filter { $0.format == .au }
                    if let match = auVendorPlugins.first(where: {
                        $0.name.localizedCaseInsensitiveContains(strippedName)
                    }) {
                        if AppLogger.shared.verbose {
                            AppLogger.shared.info(
                                "  FUZZY MATCH (vendor+strip) \"\(parsed.pluginName)\" -> \"\(match.name)\"",
                                category: "projectScan"
                            )
                        }
                        return MatchResult(matchedPluginID: "\(match.id)", isInstalled: true)
                    }
                }
            }
        }

        return matchByName(parsed, index: index)
    }

    // MARK: - VST3 Matching

    private static func matchVST3(
        _ parsed: AbletonProjectParser.ParsedPlugin,
        index: PluginIndex
    ) -> MatchResult {
        let key = "vst3:\(parsed.pluginName.lowercased())"
        if let match = index.byFormatAndName[key] {
            return MatchResult(matchedPluginID: "\(match.id)", isInstalled: true)
        }

        return matchByName(parsed, index: index)
    }

    // MARK: - VST2 Matching

    private static func matchVST2(
        _ parsed: AbletonProjectParser.ParsedPlugin,
        index: PluginIndex
    ) -> MatchResult {
        let key = "vst2:\(parsed.pluginName.lowercased())"
        if let match = index.byFormatAndName[key] {
            return MatchResult(matchedPluginID: "\(match.id)", isInstalled: true)
        }

        return matchByName(parsed, index: index)
    }

    // MARK: - Fallback Name Matching

    /// Cross-format name matching with O(1) dictionary lookups where possible,
    /// falling back to linear scans only for substring/contains matches.
    private static func matchByName(
        _ parsed: AbletonProjectParser.ParsedPlugin,
        index: PluginIndex
    ) -> MatchResult {
        let searchName = parsed.pluginName.lowercased()

        // Exact case-insensitive match (O(1) via dictionary)
        if let matches = index.byNameLower[searchName], let match = matches.first {
            return MatchResult(matchedPluginID: "\(match.id)", isInstalled: true)
        }

        // Contains match (linear scan — only reached for non-exact names)
        if let match = index.allActive.first(where: {
            $0.name.lowercased().contains(searchName)
        }) {
            return MatchResult(matchedPluginID: "\(match.id)", isInstalled: true)
        }

        // Reverse contains
        if let match = index.allActive.first(where: {
            searchName.contains($0.name.lowercased())
        }) {
            return MatchResult(matchedPluginID: "\(match.id)", isInstalled: true)
        }

        // Version suffix stripping
        let strippedName = parsed.pluginName.replacingOccurrences(
            of: #"\s*\d+(\.\d+)*$"#,
            with: "",
            options: .regularExpression
        )
        if strippedName != parsed.pluginName && !strippedName.isEmpty {
            let strippedLower = strippedName.lowercased()

            // Exact match on stripped name (O(1))
            if let matches = index.byNameLower[strippedLower], let match = matches.first {
                if AppLogger.shared.verbose {
                    AppLogger.shared.info(
                        "  FUZZY MATCH (version strip) \"\(parsed.pluginName)\" -> \"\(match.name)\"",
                        category: "projectScan"
                    )
                }
                return MatchResult(matchedPluginID: "\(match.id)", isInstalled: true)
            }
            // Contains with stripped name (linear fallback)
            if let match = index.allActive.first(where: {
                $0.name.lowercased().contains(strippedLower)
            }) {
                if AppLogger.shared.verbose {
                    AppLogger.shared.info(
                        "  FUZZY MATCH (version strip + contains) \"\(parsed.pluginName)\" -> \"\(match.name)\"",
                        category: "projectScan"
                    )
                }
                return MatchResult(matchedPluginID: "\(match.id)", isInstalled: true)
            }
        }

        // Alphanumeric normalization (O(1) via dictionary)
        let normalizedSearch = parsed.pluginName.lowercased().filter { $0.isLetter || $0.isNumber }
        if normalizedSearch.count >= 3 {
            if let match = index.byNormalizedName[normalizedSearch] {
                if AppLogger.shared.verbose {
                    AppLogger.shared.info(
                        "  FUZZY MATCH (alphanumeric) \"\(parsed.pluginName)\" -> \"\(match.name)\"",
                        category: "projectScan"
                    )
                }
                return MatchResult(matchedPluginID: "\(match.id)", isInstalled: true)
            }
        }

        return MatchResult(matchedPluginID: nil, isInstalled: false)
    }
}
