import AppKit
import Foundation

/// Fetches and caches plugin product images from bundle resources or web search.
/// Strategies (tried in order):
/// 1. VST3 Snapshots directory (standard VST3 spec)
/// 2. Large image files in bundle Resources
/// 3. Open Graph image from vendor website
/// 4. Bing Image Search
actor PluginImageService {
    static let shared = PluginImageService()

    private let cacheDir: URL
    private var memoryCache: [String: NSImage] = [:]
    private var misses: Set<String> = []

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("PluginUpdater/PluginImages")
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Returns a product image for the plugin, checking local bundle then web sources.
    func image(
        pluginName: String,
        vendorName: String,
        bundleID: String,
        pluginPath: String,
        vendorURL: String? = nil
    ) async -> NSImage? {
        let key = cacheKey(for: bundleID)

        if let cached = memoryCache[key] { return cached }
        if misses.contains(key) { return nil }

        // Disk cache
        let cacheFile = cacheDir.appendingPathComponent("\(key).png")
        if let img = loadFromDisk(cacheFile) {
            memoryCache[key] = img
            return img
        }

        // Strategy 1 & 2: Local bundle images
        if let img = findLocalImage(pluginPath: pluginPath) {
            return save(img, key: key, file: cacheFile)
        }

        // Strategy 3: Bing image search (prefers vendor domain product page images)
        if let img = await webImageSearch(name: pluginName, vendor: vendorName, vendorURL: vendorURL) {
            return save(img, key: key, file: cacheFile)
        }

        misses.insert(key)
        return nil
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

        // Resources directory — look for large images (likely artwork, not tiny icons)
        let resourcesDir = bundleURL.appendingPathComponent("Contents/Resources")
        if let img = largestImage(in: resourcesDir, fm: fm, minSize: 10_000) {
            return img
        }

        return nil
    }

    private nonisolated func largestImage(in directory: URL, fm: FileManager, minSize: Int = 0) -> NSImage? {
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            return nil
        }

        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "bmp"]
        let best = files
            .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
            .compactMap { url -> (URL, Int)? in
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size >= minSize else { return nil }
                return (url, size)
            }
            .max(by: { $0.1 < $1.1 })

        if let best {
            return NSImage(contentsOf: best.0)
        }
        return nil
    }

    // MARK: - Strategy 3: OG Image from Vendor Website

    // MARK: - Strategy 3: Web Image Search (Bing async endpoint)

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

    private nonisolated func loadFromDisk(_ file: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return NSImage(contentsOf: file)
    }

    private func save(_ image: NSImage, key: String, file: URL) -> NSImage {
        memoryCache[key] = image
        if let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: file)
        }
        return image
    }
}
