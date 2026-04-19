import Foundation

/// Processor for YouTube videos.
/// Extracts video metadata, thumbnail, and transcript from captions.
struct YouTubeProcessor: ContentProcessor {

    func canProcess(url: URL, contentType: ContentType) -> Bool {
        contentType == .youtube
    }

    func extractContent(from url: URL) async throws -> ExtractedContent {
        let videoID = extractVideoID(from: url)
        let thumbnailURL = videoID.map { URL(string: "https://img.youtube.com/vi/\($0)/maxresdefault.jpg") } ?? nil

        // Try to extract transcript from the YouTube page
        var transcript: String? = nil
        var title: String? = nil
        var author: String? = nil

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let html = String(data: data, encoding: .utf8) {
                title = extractTitleFromHTML(html)
                author = extractChannelFromHTML(html)
                transcript = try await extractTranscript(from: html)
            }
        } catch {
            print("YouTube page fetch failed: \(error)")
        }

        // Fallback to oEmbed for metadata if needed
        if title == nil, let videoID {
            let oEmbed = await fetchOEmbed(videoID: videoID)
            title = oEmbed?.title
            author = author ?? oEmbed?.author
        }

        let wordCount = transcript?.split(separator: " ").count ?? 0

        return ExtractedContent(
            title: title,
            authorName: author,
            textContent: transcript,
            thumbnailURL: thumbnailURL,
            estimatedReadTime: wordCount > 0 ? max(1, wordCount / 200) : nil,
            contentMimeType: "video/youtube"
        )
    }

    // MARK: - Video ID Extraction

    private func extractVideoID(from url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        if host.contains("youtu.be") {
            return url.pathComponents.last
        }

        if host.contains("youtube.com") {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            return components?.queryItems?.first(where: { $0.name == "v" })?.value
        }

        return nil
    }

    // MARK: - Transcript Extraction

    private func extractTranscript(from html: String) async throws -> String? {
        // Look for captions data in ytInitialPlayerResponse
        guard let captionsURL = extractCaptionsURL(from: html) else { return nil }

        let (data, _) = try await URLSession.shared.data(from: captionsURL)
        guard let xml = String(data: data, encoding: .utf8) else { return nil }

        // Strip XML tags to get plain text
        return xml.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractCaptionsURL(from html: String) -> URL? {
        // Find "captionTracks" in the page source
        guard let captionsRange = html.range(of: "captionTracks") else { return nil }
        let searchArea = String(html[captionsRange.lowerBound...].prefix(2000))

        // Look for baseUrl in the captions data
        guard let baseURLRange = searchArea.range(of: "\"baseUrl\":\"") else { return nil }
        let urlStart = baseURLRange.upperBound
        guard let urlEnd = searchArea[urlStart...].range(of: "\"") else { return nil }

        let urlString = String(searchArea[urlStart..<urlEnd.lowerBound])
            .replacingOccurrences(of: "\\u0026", with: "&")

        return URL(string: urlString)
    }

    // MARK: - HTML Metadata

    private func extractTitleFromHTML(_ html: String) -> String? {
        // Try og:title
        if let range = html.range(of: "property=\"og:title\"") {
            let area = String(html[range.lowerBound...].prefix(500))
            if let contentRange = area.range(of: "content=\""),
               let endQuote = area[contentRange.upperBound...].range(of: "\"") {
                return decodeHTMLEntities(String(area[contentRange.upperBound..<endQuote.lowerBound]))
            }
        }
        // Fallback to <title>
        if let titleStart = html.range(of: "<title>"),
           let titleEnd = html.range(of: "</title>") {
            let title = String(html[titleStart.upperBound..<titleEnd.lowerBound])
                .replacingOccurrences(of: " - YouTube", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return title.isEmpty ? nil : decodeHTMLEntities(title)
        }
        return nil
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private func extractChannelFromHTML(_ html: String) -> String? {
        // Look for channel name in link tag
        if let range = html.range(of: "\"ownerChannelName\":\"") {
            let start = range.upperBound
            let area = html[start...].prefix(200)
            if let end = area.range(of: "\"") {
                return String(area[area.startIndex..<end.lowerBound])
            }
        }
        return nil
    }

    // MARK: - oEmbed Fallback

    private struct OEmbedResult {
        let title: String?
        let author: String?
    }

    private func fetchOEmbed(videoID: String) async -> OEmbedResult? {
        guard let url = URL(string: "https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=\(videoID)&format=json") else { return nil }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return OEmbedResult(
                title: json["title"] as? String,
                author: json["author_name"] as? String
            )
        } catch {
            return nil
        }
    }
}
