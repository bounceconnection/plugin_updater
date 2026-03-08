import Foundation

/// Resolves vendor website URLs using multiple strategies, from most to least reliable.
/// Strategies (tried in order):
/// 1. Hardcoded overrides from vendor_urls.json
/// 2. URLs embedded in Info.plist fields (copyright, vendorurl, etc.)
/// 3. Reverse-domain heuristic from bundle ID with DNS + HEAD validation
/// 4. Web search fallback URL
actor VendorURLResolver {

    struct VendorURLOverride: Codable {
        let bundleIDPrefix: String
        let url: String

        enum CodingKeys: String, CodingKey {
            case bundleIDPrefix = "bundle_id_prefix"
            case url
        }
    }

    private var overrides: [VendorURLOverride] = []
    /// Cache of validated domain → URL mappings (or nil if validation failed)
    private var domainCache: [String: String?] = [:]

    /// Well-known TLDs we should try reverse-domain on.
    /// Skip anything exotic like "kontakt", "vst3", etc.
    private static let validTLDs: Set<String> = [
        "com", "net", "org", "io", "co", "de", "uk", "fr", "es", "it",
        "nl", "se", "no", "fi", "dk", "ch", "at", "au", "ca", "jp",
        "us", "me", "tv", "cc", "app", "dev", "audio", "music",
    ]

    // MARK: - Setup

    func loadOverrides() {
        if let url = Bundle.main.url(forResource: "vendor_urls", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([VendorURLOverride].self, from: data) {
            overrides = decoded
        }
    }

    // MARK: - Resolution

    /// Resolves a vendor URL for a plugin using all available strategies.
    /// - Parameters:
    ///   - bundleID: The plugin's CFBundleIdentifier
    ///   - plistFields: Raw plist dictionary values for URL extraction (optional)
    ///   - vendorName: Resolved vendor name for search fallback
    /// - Returns: The best vendor URL found, or a web search URL as last resort
    func resolve(
        bundleID: String,
        plistFields: [String: String]? = nil,
        vendorName: String? = nil
    ) async -> String? {

        // Strategy 1: Hardcoded override (highest priority — handles known edge cases)
        if let override = overrides.first(where: { bundleID.hasPrefix($0.bundleIDPrefix) }) {
            return override.url
        }

        // Strategy 2: URL embedded in plist fields
        if let fields = plistFields {
            if let url = extractURLFromPlistFields(fields) {
                return url
            }
        }

        // Strategy 3: Reverse-domain heuristic with HEAD validation
        if let url = await tryReverseDomain(bundleID: bundleID) {
            return url
        }

        // Strategy 4: Web search fallback
        if let name = vendorName, name != "Unknown" {
            return searchURL(for: name)
        }

        return nil
    }

    // MARK: - Strategy 2: Plist URL Extraction

    private func extractURLFromPlistFields(_ fields: [String: String]) -> String? {
        // Check for explicit vendor URL keys (some plugins have these)
        let urlKeys = ["vendorurl", "VendorURL", "homepage", "Homepage",
                       "website", "Website", "NSBundleHomepage"]
        for key in urlKeys {
            if let value = fields[key], isValidURL(value) {
                return normalizeURL(value)
            }
        }

        // Scan all string values for embedded URLs
        let searchFields = ["NSHumanReadableCopyright", "CFBundleGetInfoString"]
        for key in searchFields {
            if let value = fields[key], let url = extractURL(from: value) {
                return url
            }
        }

        return nil
    }

    private func extractURL(from text: String) -> String? {
        let pattern = #"https?://[^\s\"<>)}\]',]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else {
            return nil
        }
        return normalizeURL(String(text[range]))
    }

    // MARK: - Strategy 3: Reverse Domain

    private func tryReverseDomain(bundleID: String) async -> String? {
        let parts = bundleID.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        let tld = String(parts[0]).lowercased()  // "com", "de", "ch", "net", etc.
        let domain = String(parts[1])             // "fabfilter", "theusualsuspects", etc.

        // Only try well-known TLDs — skip nonsense like "kontakt", "vst3"
        guard Self.validTLDs.contains(tld) else { return nil }

        // Skip invalid domain names (underscores, spaces, all-digits, etc.)
        guard isValidDomainLabel(domain) else { return nil }

        // Skip generic domains that aren't vendor-specific
        let skip = ["apple", "mac", "audio", "music", "plugin", "plugins", "app",
                     "software", "Plugin Alliance", "mycompany", "example"]
        if skip.contains(where: { $0.caseInsensitiveCompare(domain) == .orderedSame }) {
            return nil
        }

        // Construct candidate domain
        let candidate = "\(domain).\(tld)"   // "fabfilter.com", "cableguys.de"

        // Check cache first
        if let cached = domainCache[candidate] {
            return cached
        }

        // Validate with HEAD request (try www first, then bare domain)
        let url = "https://www.\(candidate)"
        var validated = await validateURL(url)
        if validated == nil {
            validated = await validateURL("https://\(candidate)")
        }

        domainCache[candidate] = validated
        return validated
    }

    /// Checks if a string is a valid DNS label (no underscores, not all digits, reasonable length).
    private func isValidDomainLabel(_ label: String) -> Bool {
        guard label.count >= 2, label.count <= 63 else { return false }
        guard !label.contains("_") else { return false }
        guard !label.contains(" ") else { return false }
        guard label.contains(where: { $0.isLetter }) else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        return label.unicodeScalars.allSatisfy({ allowed.contains($0) })
    }

    /// Sends a HEAD request to check if a URL is reachable (follows redirects).
    /// Uses a lenient TLS session and short timeout to avoid blocking on bad certs or slow hosts.
    private func validateURL(_ urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 3

        do {
            let (_, response) = try await Self.lenientSession.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            // Accept success and redirects
            if (200..<400).contains(http.statusCode) {
                // Return the final URL after redirects
                if let finalURL = http.url?.absoluteString {
                    return finalURL
                }
                return urlString
            }
        } catch {
            // Network error — URL not reachable
        }
        return nil
    }

    /// URLSession that accepts all server certificates for HEAD-check purposes.
    /// We only use this to confirm a domain exists — not for transferring sensitive data.
    private static let lenientSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 5
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config, delegate: LenientTLSDelegate(), delegateQueue: nil)
    }()

    private final class LenientTLSDelegate: NSObject, URLSessionDelegate, @unchecked Sendable {
        func urlSession(
            _ session: URLSession,
            didReceive challenge: URLAuthenticationChallenge
        ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                return (.useCredential, URLCredential(trust: trust))
            }
            return (.performDefaultHandling, nil)
        }
    }

    // MARK: - Strategy 4: Search Fallback

    private func searchURL(for vendorName: String) -> String? {
        let query = "\(vendorName) audio plugin download"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        return "https://www.google.com/search?q=\(encoded)"
    }

    // MARK: - Helpers

    private func isValidURL(_ string: String) -> Bool {
        let lower = string.lowercased()
        return (lower.hasPrefix("http://") || lower.hasPrefix("https://"))
            && URL(string: string) != nil
    }

    private func normalizeURL(_ url: String) -> String {
        var result = url
        // Ensure https
        if result.hasPrefix("http://") {
            result = "https://" + result.dropFirst(7)
        }
        // Remove trailing punctuation that might have been captured
        while result.hasSuffix(".") || result.hasSuffix(",") || result.hasSuffix(";") {
            result = String(result.dropLast())
        }
        return result
    }
}
