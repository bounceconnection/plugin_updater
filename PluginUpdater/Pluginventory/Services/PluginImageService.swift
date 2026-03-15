import AppKit
import Foundation

/// Fetches and caches plugin product images from bundle resources or web search.
/// Strategies (tried in order):
/// 1. VST3 Snapshots directory (standard VST3 spec)
/// 2. Large, screenshot-like image files in bundle Resources (validates dimensions/ratio)
/// 3. Open Graph image from vendor website
/// 4. Bing Image Search
actor PluginImageService {
    static let shared = PluginImageService()

    private let cacheDir: URL
    private var memoryCache: [String: NSImage] = [:]
    private var misses: Set<String> = []
    private var vendorURLOverrides: [VendorURLEntry] = []
    private var inFlightKeys: [String: Task<NSImage?, Never>] = [:]

    private struct VendorURLEntry: Codable {
        let bundleIDPrefix: String
        let url: String
        enum CodingKeys: String, CodingKey {
            case bundleIDPrefix = "bundle_id_prefix"
            case url
        }
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let cache = appSupport.appendingPathComponent("Pluginventory/PluginImages")
        cacheDir = cache
        // Migrate old cache directory
        let oldCacheDir = appSupport.appendingPathComponent("PluginUpdater/PluginImages")
        if FileManager.default.fileExists(atPath: oldCacheDir.path) && !FileManager.default.fileExists(atPath: cache.path) {
            try? FileManager.default.moveItem(at: oldCacheDir, to: cache)
        }
        try? FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        let urls = Self.loadVendorURLs()
        vendorURLOverrides = urls
    }

    private static func loadVendorURLs() -> [VendorURLEntry] {
        if let url = Bundle.main.url(forResource: "vendor_urls", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([VendorURLEntry].self, from: data) {
            return decoded
        }
        return []
    }

    /// Returns the vendor website URL for a given bundle ID from vendor_urls.json.
    private func vendorWebsiteURL(for bundleID: String) -> String? {
        guard var url = vendorURLOverrides.first(where: { bundleID.hasPrefix($0.bundleIDPrefix) })?.url else {
            return nil
        }
        if url.hasPrefix("http://") {
            url = "https://" + url.dropFirst(7)
        }
        return url
    }

    /// Returns `true` if an image (or confirmed miss) is already cached for this plugin.
    /// Checks memory cache, disk cache, and misses set — never triggers a fetch.
    func hasCachedImage(pluginName: String, vendorName: String, bundleID: String) -> Bool {
        let key = cacheKey(for: bundleID)
        let shared = sharedCacheKey(name: pluginName, vendor: vendorName)

        if memoryCache[key] != nil || memoryCache[shared] != nil { return true }
        if misses.contains(shared) { return true }

        let cacheFile = cacheDir.appendingPathComponent("\(key).png")
        let sharedCacheFile = cacheDir.appendingPathComponent("\(shared).png")
        let fm = FileManager.default
        return fm.fileExists(atPath: cacheFile.path) || fm.fileExists(atPath: sharedCacheFile.path)
    }

    /// Clears all cached images (memory and disk) so they are re-fetched on next access.
    func clearCache() {
        memoryCache.removeAll()
        misses.removeAll()
        inFlightKeys.removeAll()
        if let files = try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// Returns a product image for the plugin, checking local bundle then web sources.
    /// Images are shared across formats of the same plugin via a name+vendor shared key.
    /// Deduplicates concurrent fetches for the same shared key.
    func image(
        pluginName: String,
        vendorName: String,
        bundleID: String,
        pluginPath: String,
        vendorURL: String? = nil
    ) async -> NSImage? {
        let key = cacheKey(for: bundleID)
        let shared = sharedCacheKey(name: pluginName, vendor: vendorName)

        if let cached = memoryCache[key] { return cached }
        if let cached = memoryCache[shared] {
            memoryCache[key] = cached
            return cached
        }
        if misses.contains(shared) { return nil }

        // Disk cache — check bundle-specific first, then shared
        let cacheFile = cacheDir.appendingPathComponent("\(key).png")
        let sharedCacheFile = cacheDir.appendingPathComponent("\(shared).png")
        for file in [cacheFile, sharedCacheFile] {
            if let img = loadFromDisk(file) {
                memoryCache[key] = img
                memoryCache[shared] = img
                return img
            }
        }

        // In-flight dedup: if another caller is already fetching this shared key, await it
        if let existing = inFlightKeys[shared] {
            return await existing.value
        }

        let task = Task<NSImage?, Never> {
            // Strategy 1 & 2: Local bundle images (with validation for Resources)
            if let img = findLocalImage(pluginPath: pluginPath) {
                return save(img, key: key, sharedKey: shared)
            }

            // Strategy 3: OG image from vendor website
            let resolvedVendorURL = vendorURL ?? vendorWebsiteURL(for: bundleID)
            if let siteURL = resolvedVendorURL {
                if let img = await fetchOGImage(from: siteURL) {
                    return save(img, key: key, sharedKey: shared)
                }
            }

            // Strategy 4: Bing image search (prefers vendor domain product page images)
            if let img = await webImageSearch(name: pluginName, vendor: vendorName, vendorURL: resolvedVendorURL) {
                return save(img, key: key, sharedKey: shared)
            }

            misses.insert(shared)
            return nil
        }

        inFlightKeys[shared] = task
        let result = await task.value
        inFlightKeys.removeValue(forKey: shared)
        return result
    }

    // MARK: - Strategy 1 & 2: Local Bundle Images

    private nonisolated func findLocalImage(pluginPath: String) -> NSImage? {
        let bundleURL = URL(fileURLWithPath: pluginPath)
        let fm = FileManager.default

        // VST3 Snapshots directory (standard VST3 spec — plugin GUI screenshots)
        let snapshotsDir = bundleURL.appendingPathComponent("Contents/Resources/Snapshots")
        if let img = largestImage(in: snapshotsDir, fm: fm) {
            return img
        }

        // Resources directory — look for large images that look like product screenshots.
        // Many plugins store UI textures (knob spritesheets, skin tiles) here, so we
        // validate dimensions and aspect ratio to reject those.
        let resourcesDir = bundleURL.appendingPathComponent("Contents/Resources")
        if let img = largestImage(in: resourcesDir, fm: fm, minSize: 10_000, validateScreenshot: true) {
            return img
        }

        return nil
    }

    /// Common filename patterns for internal UI assets (not product screenshots).
    private static let uiAssetPatterns = [
        "knob", "slider", "button", "background", "bg_", "skin", "dial", "fader",
        "meter", "led_", "icon", "sprite", "overlay", "texture", "cursor", "font",
        "beetle", "egg", "bubble",
    ]

    private nonisolated func largestImage(
        in directory: URL,
        fm: FileManager,
        minSize: Int = 0,
        validateScreenshot: Bool = false
    ) -> NSImage? {
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "bmp"]

        let candidates = files
            .filter { url in
                let ext = url.pathExtension.lowercased()
                guard imageExtensions.contains(ext) else { return false }

                if validateScreenshot {
                    let name = url.deletingPathExtension().lastPathComponent.lowercased()
                    if Self.uiAssetPatterns.contains(where: { name.contains($0) }) { return false }
                }
                return true
            }
            .compactMap { url -> (URL, Int)? in
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size >= minSize else { return nil }
                return (url, size)
            }
            .sorted { $0.1 > $1.1 }

        for (url, _) in candidates {
            guard let img = NSImage(contentsOf: url) else { continue }

            if validateScreenshot {
                // Must be reasonably sized and proportioned to be a product screenshot
                guard img.size.width >= 200,
                      img.size.height >= 200,
                      isReasonableAspectRatio(img) else { continue }
            }

            return img
        }

        return nil
    }

    // MARK: - Strategy 3: OG Image from Vendor Website

    private func fetchOGImage(from websiteURL: String) async -> NSImage? {
        var sanitized = websiteURL
        if sanitized.hasPrefix("http://") {
            sanitized = "https://" + sanitized.dropFirst(7)
        }
        guard let url = URL(string: sanitized) else { return nil }

        var request = URLRequest(url: url, timeoutInterval: 8)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Extract og:image or twitter:image content
        guard var imageURLString = extractOGImageURL(from: html),
              !imageURLString.isEmpty else {
            return nil
        }

        // Upgrade HTTP to HTTPS to comply with App Transport Security
        if imageURLString.hasPrefix("http://") {
            imageURLString = "https://" + imageURLString.dropFirst(7)
        }

        guard let imageURL = URL(string: imageURLString, relativeTo: url)?.absoluteURL else {
            return nil
        }

        var imgRequest = URLRequest(url: imageURL, timeoutInterval: 8)
        imgRequest.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (imgData, imgResp) = try? await URLSession.shared.data(for: imgRequest),
              let imgHTTP = imgResp as? HTTPURLResponse,
              imgHTTP.statusCode == 200,
              let img = NSImage(data: imgData),
              img.size.width >= 100, img.size.height >= 100,
              isReasonableAspectRatio(img) else {
            return nil
        }

        return img
    }

    /// Extracts the og:image or twitter:image URL from HTML.
    private nonisolated func extractOGImageURL(from html: String) -> String? {
        // Try og:image first, then twitter:image
        let patterns = [
            #"<meta[^>]*property\s*=\s*"og:image"[^>]*content\s*=\s*"([^"]+)""#,
            #"<meta[^>]*content\s*=\s*"([^"]+)"[^>]*property\s*=\s*"og:image""#,
            #"<meta[^>]*name\s*=\s*"twitter:image"[^>]*content\s*=\s*"([^"]+)""#,
            #"<meta[^>]*content\s*=\s*"([^"]+)"[^>]*name\s*=\s*"twitter:image""#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                  let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html) else { continue }
            let urlString = String(html[range])
            if !urlString.isEmpty { return urlString }
        }

        return nil
    }

    // MARK: - Strategy 4: Web Image Search (Bing async endpoint)

    private struct ImageCandidate {
        let imageURL: URL
        let pageHost: String?
    }

    private func webImageSearch(name: String, vendor: String, vendorURL: String? = nil) async -> NSImage? {
        let query = "\(name) \(vendor) audio plugin"
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let searchURL = URL(string: "https://www.bing.com/images/async?q=\(encoded)&first=0&count=10&mmasync=1") else {
            return nil
        }

        var request = URLRequest(url: searchURL, timeoutInterval: 10)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse,
              http.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Extract candidates with their source page URLs
        let candidates = extractImageCandidates(from: html)

        // Prioritize: vendor domain images first, then others
        let vendorHost = vendorURL.flatMap { URL(string: $0)?.host?.replacingOccurrences(of: "www.", with: "") }
        let sorted = candidates.sorted { a, b in
            let aIsVendor = vendorHost != nil && (a.pageHost?.contains(vendorHost!) == true)
            let bIsVendor = vendorHost != nil && (b.pageHost?.contains(vendorHost!) == true)
            if aIsVendor != bIsVendor { return aIsVendor }
            return false
        }

        // Try each candidate until one downloads successfully
        for candidate in sorted.prefix(5) {
            var imgRequest = URLRequest(url: candidate.imageURL, timeoutInterval: 8)
            imgRequest.setValue(
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15",
                forHTTPHeaderField: "User-Agent"
            )

            guard let (imgData, imgResp) = try? await URLSession.shared.data(for: imgRequest),
                  let imgHTTP = imgResp as? HTTPURLResponse,
                  imgHTTP.statusCode == 200,
                  let img = NSImage(data: imgData),
                  img.size.width >= 100, img.size.height >= 100,
                  isReasonableAspectRatio(img) else {
                continue
            }
            return img
        }

        return nil
    }

    private func extractImageCandidates(from html: String) -> [ImageCandidate] {
        // Bing async endpoint: each result has purl (page) and murl (image) in HTML-entity-encoded JSON
        let pattern = #"purl&quot;:&quot;(https?://[^&]+?)&quot;.*?murl&quot;:&quot;(https?://[^&]+?)&quot;"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(in: html, range: NSRange(html.startIndex..., in: html))

        var candidates: [ImageCandidate] = []
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let purlRange = Range(match.range(at: 1), in: html),
                  let murlRange = Range(match.range(at: 2), in: html) else { continue }

            let pageURLString = String(html[purlRange]).replacingOccurrences(of: "&amp;", with: "&")
            var imageURLString = String(html[murlRange]).replacingOccurrences(of: "&amp;", with: "&")

            if imageURLString.hasPrefix("http://") {
                imageURLString = "https://" + imageURLString.dropFirst(7)
            }

            let lower = imageURLString.lowercased()
            if lower.contains("favicon") || lower.contains("logo") || lower.contains("avatar") { continue }
            if lower.contains("_thumb") || lower.contains("_small") { continue }

            guard let imageURL = URL(string: imageURLString) else { continue }
            let pageHost = URL(string: pageURLString)?.host?.replacingOccurrences(of: "www.", with: "")

            candidates.append(ImageCandidate(imageURL: imageURL, pageHost: pageHost))
        }

        return candidates
    }

    // MARK: - Helpers

    /// Rejects banners/strips (too wide) and tall slivers (too narrow).
    private nonisolated func isReasonableAspectRatio(_ image: NSImage) -> Bool {
        let w = image.size.width
        let h = image.size.height
        guard h > 0, w > 0 else { return false }
        let ratio = w / h
        return ratio >= 0.3 && ratio <= 4.0
    }

    private func cacheKey(for bundleID: String) -> String {
        bundleID.replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    /// Shared key based on plugin name + vendor so different formats share the same image.
    private func sharedCacheKey(name: String, vendor: String) -> String {
        let raw = "\(vendor)_\(name)"
        return raw.lowercased()
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private nonisolated func loadFromDisk(_ file: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return NSImage(contentsOf: file)
    }

    private func save(_ image: NSImage, key: String, sharedKey: String) -> NSImage {
        memoryCache[key] = image
        memoryCache[sharedKey] = image
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            let cacheFile = cacheDir.appendingPathComponent("\(key).png")
            try? png.write(to: cacheFile)
            let sharedFile = cacheDir.appendingPathComponent("\(sharedKey).png")
            if !FileManager.default.fileExists(atPath: sharedFile.path) {
                try? png.write(to: sharedFile)
            }
        }
        return image
    }
}
