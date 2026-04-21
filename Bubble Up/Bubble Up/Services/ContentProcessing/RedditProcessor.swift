import Foundation

/// Extracts content from Reddit posts using Reddit's public JSON API.
/// Reddit's web pages are heavily JavaScript-rendered and fail generic HTML scraping,
/// but appending `.json` to any post URL returns structured data with title, body,
/// author, and top-level comments.
struct RedditProcessor: ContentProcessor {

    func canProcess(url: URL, contentType: ContentType) -> Bool {
        contentType == .reddit
    }

    func extractContent(from url: URL) async throws -> ExtractedContent {
        let jsonURL = try await resolveJSONURL(for: url)

        var request = URLRequest(url: jsonURL)
        // Reddit blocks requests lacking a User-Agent. Using a descriptive, unique
        // identifier is Reddit's recommendation for third-party clients.
        request.setValue("BubbleUp/1.0 (iOS Reading App)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ContentProcessorError.extractionFailed("Reddit returned non-200 status")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [Any] else {
            throw ContentProcessorError.extractionFailed("Unexpected Reddit JSON shape")
        }

        // Reddit's post JSON is an array of two listings:
        //   [0] = the post itself (wrapped in a Listing),
        //   [1] = the comment tree.
        guard let postListing = json.first as? [String: Any],
              let postData = (postListing["data"] as? [String: Any])?["children"] as? [[String: Any]],
              let post = (postData.first?["data"]) as? [String: Any] else {
            throw ContentProcessorError.extractionFailed("Could not locate post data in Reddit response")
        }

        let title = (post["title"] as? String)?.decodedHTMLEntities()
        let author = post["author"] as? String
        let selfText = (post["selftext"] as? String)?.decodedHTMLEntities() ?? ""
        let subreddit = post["subreddit_name_prefixed"] as? String
        let thumbnailURL = Self.pickThumbnail(from: post)

        // Walk the top of the comment tree. Along the way we extract:
        //   - a stickied moderator/bot "TL;DR of the discussion" comment, if present
        //   - up to 5 organic top-level comments (excluding the TL;DR one)
        var discussionSummary: SocialPostContent.DiscussionSummary?
        var topComments: [SocialPostContent.Comment] = []
        if json.count > 1,
           let commentsListing = json[1] as? [String: Any],
           let commentsData = (commentsListing["data"] as? [String: Any])?["children"] as? [[String: Any]] {
            for child in commentsData {
                guard let kind = child["kind"] as? String, kind == "t1",
                      let data = child["data"] as? [String: Any],
                      let body = data["body"] as? String,
                      let commentAuthor = data["author"] as? String else { continue }
                let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed != "[deleted]", trimmed != "[removed]" else { continue }
                let decoded = trimmed.decodedHTMLEntities()

                if discussionSummary == nil, Self.isDiscussionSummary(data: data, body: decoded) {
                    discussionSummary = .init(author: commentAuthor, body: decoded)
                    continue
                }

                topComments.append(.init(author: commentAuthor, body: decoded))
                if topComments.count >= 5 { break }
            }
        }

        let structured = SocialPostContent(
            platform: .reddit,
            authorDisplayName: nil,
            authorHandle: author.map { "u/\($0)" },
            subreddit: subreddit,
            body: selfText,
            discussionSummary: discussionSummary,
            topComments: topComments,
            mediaCount: 0,
            hasVideo: false
        )
        let textContent = SocialPostCodec.encode(structured)
        let wordCount = textContent.split(separator: " ").count
        let estimatedReadTime = wordCount > 0 ? max(1, wordCount / 200) : nil

        return ExtractedContent(
            title: title,
            authorName: author.map { "u/\($0)" },
            textContent: textContent.isEmpty ? nil : textContent,
            thumbnailURL: thumbnailURL,
            estimatedReadTime: estimatedReadTime,
            contentMimeType: "application/reddit"
        )
    }

    // MARK: - URL Handling

    /// Returns the JSON-API equivalent of a Reddit URL. Handles `redd.it` short links
    /// by following their redirect to the canonical www.reddit.com URL first.
    private func resolveJSONURL(for url: URL) async throws -> URL {
        var workingURL = url
        let host = url.host?.lowercased() ?? ""

        if host == "redd.it" || host.hasSuffix(".redd.it") {
            workingURL = try await followRedirect(from: url)
        }

        // Normalize host to www.reddit.com (avoids old.reddit.com / np.reddit.com variants).
        guard var components = URLComponents(url: workingURL, resolvingAgainstBaseURL: false) else {
            throw ContentProcessorError.extractionFailed("Invalid Reddit URL")
        }
        components.host = "www.reddit.com"

        // Strip trailing slash, then append `.json`.
        var path = components.path
        if path.hasSuffix("/") { path.removeLast() }
        if !path.hasSuffix(".json") { path += ".json" }
        components.path = path

        // Request only the first page of comments; we only take the top few.
        var queryItems = components.queryItems ?? []
        queryItems.removeAll { $0.name == "raw_json" || $0.name == "limit" }
        queryItems.append(URLQueryItem(name: "raw_json", value: "1"))
        queryItems.append(URLQueryItem(name: "limit", value: "10"))
        components.queryItems = queryItems

        guard let jsonURL = components.url else {
            throw ContentProcessorError.extractionFailed("Could not build Reddit JSON URL")
        }
        return jsonURL
    }

    private func followRedirect(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.setValue("BubbleUp/1.0 (iOS Reading App)", forHTTPHeaderField: "User-Agent")
        let (_, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, let finalURL = http.url {
            return finalURL
        }
        return url
    }

    /// Heuristic for spotting a moderator- or bot-posted thread summary comment
    /// (the "TL;DR of the discussion generated automatically…" pattern).
    ///
    /// We require one strong structural signal (stickied or mod-distinguished)
    /// plus a keyword cue in the body, OR a known auto-TLDR bot author. This
    /// keeps us from flagging routine stickied rule-reminders or plain mod
    /// comments.
    private static func isDiscussionSummary(data: [String: Any], body: String) -> Bool {
        let author = (data["author"] as? String)?.lowercased() ?? ""
        let stickied = (data["stickied"] as? Bool) ?? false
        let distinguished = (data["distinguished"] as? String) ?? ""
        let isMod = distinguished == "moderator" || distinguished == "admin"

        // Known auto-TLDR bot accounts (common across several subreddits).
        let tldrBots: Set<String> = [
            "autotldr", "auto_tldr_bot", "tldrbot", "summarybot",
            "thread_tldr_bot", "tl_dr_bot"
        ]
        if tldrBots.contains(author) { return true }

        // Structural signal required: stickied OR mod/admin flair.
        guard stickied || isMod else { return false }

        // Keyword cue in the first line — keeps us from matching routine
        // stickied comments (rule reminders, AutoMod warnings).
        let firstLine = body.split(separator: "\n").first.map(String.init)?
            .lowercased() ?? body.lowercased()
        let cues = ["tl;dr", "tldr", "tl dr", "thread summary", "discussion summary",
                    "auto-summary", "automatic summary", "generated summary"]
        return cues.contains { firstLine.contains($0) }
    }

    private static func pickThumbnail(from post: [String: Any]) -> URL? {
        // Prefer the OG-image-like preview if available; fall back to the thumbnail field.
        if let preview = post["preview"] as? [String: Any],
           let images = preview["images"] as? [[String: Any]],
           let source = images.first?["source"] as? [String: Any],
           let urlString = source["url"] as? String {
            // Reddit HTML-encodes `&` as `&amp;` in JSON preview URLs.
            let cleaned = urlString.replacingOccurrences(of: "&amp;", with: "&")
            if let url = URL(string: cleaned) { return url }
        }
        if let thumb = post["thumbnail"] as? String,
           thumb.hasPrefix("http"),
           let url = URL(string: thumb) {
            return url
        }
        return nil
    }
}

private extension String {
    func decodedHTMLEntities() -> String {
        self
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
