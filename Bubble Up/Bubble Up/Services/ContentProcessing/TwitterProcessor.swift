import Foundation

/// Extracts content from X.com / Twitter status URLs.
///
/// X.com's public pages require JavaScript to render the tweet, so generic HTML
/// scraping returns empty text. This processor first tries Twitter's public
/// syndication endpoint (`cdn.syndication.twimg.com`) which returns the full
/// tweet as JSON without authentication, and falls back to oEmbed if that
/// endpoint changes its shape or blocks the request.
struct TwitterProcessor: ContentProcessor {

    func canProcess(url: URL, contentType: ContentType) -> Bool {
        contentType == .twitter
    }

    func extractContent(from url: URL) async throws -> ExtractedContent {
        let resolvedURL = try await resolveShortLinkIfNeeded(url)

        guard let tweetID = Self.extractTweetID(from: resolvedURL) else {
            throw ContentProcessorError.extractionFailed("Could not locate tweet ID in URL")
        }

        if let viaSyndication = try? await fetchViaSyndication(tweetID: tweetID) {
            return viaSyndication
        }

        // Fallback: oEmbed returns at least the tweet text inside a <blockquote>.
        return try await fetchViaOEmbed(tweetID: tweetID, canonicalURL: resolvedURL)
    }

    // MARK: - Syndication

    private func fetchViaSyndication(tweetID: String) async throws -> ExtractedContent {
        // The syndication endpoint requires a `token` query param derived from the ID.
        // The widely-used algorithm: ((Double(tweetID) ?? 0) / 1e15 * π) expressed in base 36.
        let token = Self.syndicationToken(for: tweetID)

        var components = URLComponents(string: "https://cdn.syndication.twimg.com/tweet-result")!
        components.queryItems = [
            URLQueryItem(name: "id", value: tweetID),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "token", value: token)
        ]

        guard let url = components.url else {
            throw ContentProcessorError.extractionFailed("Could not build syndication URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (BubbleUp iOS Reading App)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ContentProcessorError.extractionFailed("Syndication endpoint returned non-200")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ContentProcessorError.extractionFailed("Unexpected syndication JSON shape")
        }

        let text = (json["text"] as? String) ?? ""
        let userDict = json["user"] as? [String: Any]
        let authorName = userDict?["name"] as? String
        let authorHandle = userDict?["screen_name"] as? String

        // Prefer a media image if attached; otherwise fall back to the author avatar.
        let thumbnailURL = Self.pickThumbnail(from: json)

        let photoCount = (json["photos"] as? [[String: Any]])?.count ?? 0
        let hasVideo = json["video"] != nil

        let post = SocialPostContent(
            platform: .twitter,
            authorDisplayName: authorName,
            authorHandle: authorHandle.map { "@\($0)" },
            subreddit: nil,
            body: text,
            discussionSummary: nil,
            topComments: [],
            mediaCount: photoCount,
            hasVideo: hasVideo
        )
        let textContent = SocialPostCodec.encode(post)
        let wordCount = textContent.split(separator: " ").count

        // Intentionally leave title nil: the tweet body has no natural title, so
        // the summary AI generates a concise one. The author handle is displayed
        // separately in the card's meta line, so synthesizing "{author}: {snippet}"
        // here would duplicate that and produce long, unreadable headlines.
        return ExtractedContent(
            title: nil,
            authorName: authorHandle.map { "@\($0)" } ?? authorName,
            textContent: textContent.isEmpty ? nil : textContent,
            thumbnailURL: thumbnailURL,
            estimatedReadTime: wordCount > 0 ? max(1, wordCount / 200) : nil,
            contentMimeType: "application/twitter"
        )
    }

    /// Replicates the token algorithm used by Twitter's embeddable widgets:
    /// `((Number(id) / 1e15) * Math.PI).toString(36).replace(/(0+|\.)/g, '')`.
    /// Produces a short base-36 string unique to the tweet ID.
    private static func syndicationToken(for tweetID: String) -> String {
        guard let id = Double(tweetID) else { return "0" }
        let value = (id / 1e15) * .pi
        return base36Fractional(value)
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: "0", with: "")
    }

    /// JavaScript's `Number.prototype.toString(36)` for a positive fractional in [0, 1e6).
    /// Emits up to 12 fractional digits, which matches the resolution of Twitter's widget.
    private static func base36Fractional(_ input: Double) -> String {
        let digits = Array("0123456789abcdefghijklmnopqrstuvwxyz")
        let value = abs(input)
        let integerPart = Int(value.rounded(.down))
        var result = String(integerPart, radix: 36)
        var fractional = value - Double(integerPart)
        guard fractional > 0 else { return result }
        result.append(".")
        for _ in 0..<12 {
            fractional *= 36
            let digit = Int(fractional.rounded(.down))
            let clamped = max(0, min(35, digit))
            result.append(digits[clamped])
            fractional -= Double(clamped)
            if fractional <= 0 { break }
        }
        return result
    }

    // MARK: - oEmbed Fallback

    private func fetchViaOEmbed(tweetID: String, canonicalURL: URL) async throws -> ExtractedContent {
        var components = URLComponents(string: "https://publish.twitter.com/oembed")!
        components.queryItems = [
            URLQueryItem(name: "url", value: canonicalURL.absoluteString),
            URLQueryItem(name: "omit_script", value: "true"),
            URLQueryItem(name: "hide_thread", value: "false"),
            URLQueryItem(name: "dnt", value: "true")
        ]

        guard let url = components.url else {
            throw ContentProcessorError.extractionFailed("Could not build oEmbed URL")
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ContentProcessorError.extractionFailed("Twitter oEmbed returned non-200")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ContentProcessorError.extractionFailed("Unexpected oEmbed JSON shape")
        }

        let html = (json["html"] as? String) ?? ""
        let authorName = json["author_name"] as? String
        let authorURLString = json["author_url"] as? String
        let handle = authorURLString.flatMap(Self.handleFromAuthorURL)

        let tweetText = Self.extractTweetText(fromOEmbedHTML: html)

        let post = SocialPostContent(
            platform: .twitter,
            authorDisplayName: authorName,
            authorHandle: handle.map { "@\($0)" },
            subreddit: nil,
            body: tweetText,
            discussionSummary: nil,
            topComments: [],
            mediaCount: 0,
            hasVideo: false
        )
        let textContent = SocialPostCodec.encode(post)
        let wordCount = textContent.split(separator: " ").count

        // See rationale in fetchViaSyndication — AI generates a concise title
        // for tweets rather than synthesizing one from author + snippet.
        return ExtractedContent(
            title: nil,
            authorName: handle.map { "@\($0)" } ?? authorName,
            textContent: textContent.isEmpty ? nil : textContent,
            thumbnailURL: nil,
            estimatedReadTime: wordCount > 0 ? max(1, wordCount / 200) : nil,
            contentMimeType: "application/twitter"
        )
    }

    // MARK: - Helpers

    /// Pulls the tweet ID from `/status/<id>` or `/i/status/<id>` paths.
    static func extractTweetID(from url: URL) -> String? {
        let components = url.pathComponents
        guard let statusIndex = components.firstIndex(of: "status"),
              components.index(after: statusIndex) < components.endIndex else {
            return nil
        }
        let idCandidate = components[components.index(after: statusIndex)]
        // Tweet IDs are numeric; reject anything else to avoid "photo", "video", etc.
        return idCandidate.allSatisfy(\.isNumber) ? idCandidate : nil
    }

    private static func pickThumbnail(from json: [String: Any]) -> URL? {
        if let photos = json["photos"] as? [[String: Any]],
           let first = photos.first,
           let urlString = first["url"] as? String,
           let url = URL(string: urlString) {
            return url
        }
        if let mediaDetails = json["mediaDetails"] as? [[String: Any]],
           let first = mediaDetails.first,
           let urlString = first["media_url_https"] as? String,
           let url = URL(string: urlString) {
            return url
        }
        if let user = json["user"] as? [String: Any],
           let avatar = user["profile_image_url_https"] as? String,
           let url = URL(string: avatar.replacingOccurrences(of: "_normal", with: "_400x400")) {
            return url
        }
        return nil
    }

    private static func handleFromAuthorURL(_ urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }
        return url.pathComponents.last(where: { !$0.isEmpty && $0 != "/" })
    }

    /// oEmbed returns the tweet wrapped in a <blockquote>. Strip the HTML and drop the
    /// trailing "— Author (@handle) Date" attribution line we already capture above.
    private static func extractTweetText(fromOEmbedHTML html: String) -> String {
        guard let blockStart = html.range(of: "<blockquote"),
              let pStart = html.range(of: "<p", range: blockStart.upperBound..<html.endIndex),
              let pContentStart = html.range(of: ">", range: pStart.upperBound..<html.endIndex),
              let pEnd = html.range(of: "</p>", range: pContentStart.upperBound..<html.endIndex) else {
            return ""
        }
        let inner = String(html[pContentStart.upperBound..<pEnd.lowerBound])
        let stripped = inner.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Follows `t.co` short links to the underlying x.com URL.
    private func resolveShortLinkIfNeeded(_ url: URL) async throws -> URL {
        guard url.host?.lowercased() == "t.co" else { return url }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("Mozilla/5.0 (BubbleUp iOS Reading App)", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, let finalURL = http.url {
            return finalURL
        }
        return url
    }
}
