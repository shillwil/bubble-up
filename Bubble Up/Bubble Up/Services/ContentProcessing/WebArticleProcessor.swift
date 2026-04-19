import Foundation

/// Extracts readable content from web articles.
struct WebArticleProcessor: ContentProcessor {

    func canProcess(url: URL, contentType: ContentType) -> Bool {
        contentType == .webArticle
    }

    func extractContent(from url: URL) async throws -> ExtractedContent {
        // Fetch the page HTML
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ContentProcessorError.extractionFailed("Failed to fetch URL")
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ContentProcessorError.extractionFailed("Could not decode HTML")
        }

        // Basic content extraction (title and body text)
        let title = extractTitle(from: html)
        let textContent = extractReadableText(from: html)
        let wordCount = textContent.split(separator: " ").count
        let estimatedReadTime = max(1, wordCount / 200)

        return ExtractedContent(
            title: title,
            authorName: extractAuthor(from: html),
            textContent: textContent,
            thumbnailURL: extractOGImage(from: html),
            estimatedReadTime: estimatedReadTime,
            contentMimeType: "text/html"
        )
    }

    // MARK: - HTML Parsing Helpers

    private func extractTitle(from html: String) -> String? {
        // Try og:title first
        if let ogTitle = extractMetaContent(from: html, property: "og:title") {
            return decodeHTMLEntities(ogTitle)
        }
        // Fallback to <title> tag
        if let titleRange = html.range(of: "<title>"),
           let endRange = html.range(of: "</title>") {
            let start = titleRange.upperBound
            let end = endRange.lowerBound
            if start < end {
                return decodeHTMLEntities(String(html[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return nil
    }

    private func extractAuthor(from html: String) -> String? {
        if let author = extractMetaContent(from: html, name: "author") {
            return decodeHTMLEntities(author)
        }
        return nil
    }

    private func extractOGImage(from html: String) -> URL? {
        guard let urlString = extractMetaContent(from: html, property: "og:image") else { return nil }
        return URL(string: urlString)
    }

    private func extractMetaContent(from html: String, property: String? = nil, name: String? = nil) -> String? {
        let searchKey: String
        if let property {
            searchKey = "property=\"\(property)\""
        } else if let name {
            searchKey = "name=\"\(name)\""
        } else {
            return nil
        }

        guard let metaRange = html.range(of: searchKey) else { return nil }

        // Look for content attribute nearby
        let searchArea = html[metaRange.lowerBound...]
        let prefix = String(searchArea.prefix(500))

        if let contentRange = prefix.range(of: "content=\""),
           let endQuote = prefix[contentRange.upperBound...].range(of: "\"") {
            return decodeHTMLEntities(String(prefix[contentRange.upperBound..<endQuote.lowerBound]))
        }
        return nil
    }

    private func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#38;", with: "&")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private func extractReadableText(from html: String) -> String {
        var text = html

        // Remove script and style blocks
        text = removeHTMLBlocks(from: text, tag: "script")
        text = removeHTMLBlocks(from: text, tag: "style")
        text = removeHTMLBlocks(from: text, tag: "nav")
        text = removeHTMLBlocks(from: text, tag: "header")
        text = removeHTMLBlocks(from: text, tag: "footer")

        // Remove all remaining HTML tags
        text = text.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )

        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")

        // Collapse whitespace
        text = text.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func removeHTMLBlocks(from html: String, tag: String) -> String {
        html.replacingOccurrences(
            of: "<\(tag)[^>]*>.*?</\(tag)>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
    }
}
