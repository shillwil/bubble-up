import Foundation

/// Lightweight summarizer for the share extension. Reads BYOK API keys from
/// App Group UserDefaults (synced by the main app) and calls Gemini/Claude/OpenAI
/// directly to pre-generate summaries before the user opens the app.
enum ShareExtensionSummarizer {

    private static let appGroupSuite = "group.com.shillwil.bubble-up"

    struct SummaryResult: Codable {
        let summary: String
        let bullets: [String]
        let estimatedReadTime: Int?
    }

    // MARK: - Public

    /// Attempts to generate a summary for the given URL. Returns nil if no API key
    /// is available or if content extraction/summarization fails.
    static func generateSummary(url: String, title: String?, userNotes: String?) async -> SummaryResult? {
        guard let defaults = UserDefaults(suiteName: appGroupSuite) else { return nil }

        // Try providers in order: Gemini → Claude → OpenAI
        if let key = defaults.string(forKey: "com.shillwil.bubble-up.gemini-api-key") {
            return await summarizeWithGemini(apiKey: key, url: url, title: title, userNotes: userNotes)
        }
        if let key = defaults.string(forKey: "com.shillwil.bubble-up.claude-api-key") {
            return await summarizeWithClaude(apiKey: key, url: url, title: title, userNotes: userNotes)
        }
        if let key = defaults.string(forKey: "com.shillwil.bubble-up.openai-api-key") {
            return await summarizeWithOpenAI(apiKey: key, url: url, title: title, userNotes: userNotes)
        }

        return nil // No BYOK key available
    }

    // MARK: - Content Extraction

    /// Simple HTML-to-text extraction. Fetches the URL and strips tags.
    private static func extractContent(from urlString: String) async -> String? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            let (data, _) = try await URLSession.shared.data(for: request)
            guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .ascii) else { return nil }
            return stripHTML(html)
        } catch {
            return nil
        }
    }

    private static func stripHTML(_ html: String) -> String {
        // Remove script and style blocks
        var text = html
        let blockPatterns = ["<script[^>]*>[\\s\\S]*?</script>", "<style[^>]*>[\\s\\S]*?</style>"]
        for pattern in blockPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                text = regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
            }
        }
        // Strip remaining tags
        if let tagRegex = try? NSRegularExpression(pattern: "<[^>]+>") {
            text = tagRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        // Decode common HTML entities
        text = text.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        // Collapse whitespace
        if let wsRegex = try? NSRegularExpression(pattern: "\\s+") {
            text = wsRegex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: " ")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prompt

    private static func buildPrompt(content: String, title: String?, url: String, userNotes: String?) -> String {
        var prompt = """
        Summarize the following article. Return your response as a JSON object with this exact structure:
        {
            "summary": "A 1-2 sentence summary stating the article's core argument or finding",
            "bullets": ["bullet point 1", "bullet point 2", "bullet point 3"],
            "estimatedReadTime": 5
        }

        Rules:
        - The summary MUST state what the article argues, claims, or reveals — not just what it's "about." Include specific names, numbers, or concrete details when available. Bad: "This article discusses the impact of AI on healthcare." Good: "Researchers at Johns Hopkins found that GPT-4 diagnosed rare skin conditions with 92% accuracy, outperforming dermatology residents."
        - Provide exactly 3 bullet points. Each should highlight a surprising, non-obvious, or actionable insight — not a generic description. Prioritize takeaways the reader couldn't guess from the title alone.
        - estimatedReadTime is in minutes, estimated based on article length (~250 words per minute)
        - The reader saved this article to read later. The summary should help them decide when to prioritize reading the full piece.
        - Return ONLY the JSON object, no other text
        """

        if let notes = userNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            prompt += """

            The reader noted why they saved this: "\(notes)"
            Tailor your summary and bullet points toward their stated interest while still accurately representing the article.
            """
        }

        prompt += """


        Title: \(title ?? "Unknown")
        URL: \(url)

        Article content:
        \(String(content.prefix(8000)))
        """

        return prompt
    }

    // MARK: - Gemini

    private static func summarizeWithGemini(apiKey: String, url: String, title: String?, userNotes: String?) async -> SummaryResult? {
        guard let content = await extractContent(from: url), !content.isEmpty else { return nil }

        let prompt = buildPrompt(content: content, title: title, url: url, userNotes: userNotes)
        let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=\(apiKey)")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 25

        let body: [String: Any] = [
            "contents": [["parts": [["text": prompt]]]],
            "generationConfig": ["responseMimeType": "application/json"]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String,
                  let textData = text.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(SummaryResult.self, from: textData)
        } catch {
            return nil
        }
    }

    // MARK: - Claude

    private static func summarizeWithClaude(apiKey: String, url: String, title: String?, userNotes: String?) async -> SummaryResult? {
        guard let content = await extractContent(from: url), !content.isEmpty else { return nil }

        let prompt = buildPrompt(content: content, title: title, url: url, userNotes: userNotes)
        let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 25

        let body: [String: Any] = [
            "model": "claude-sonnet-4-6-20250514",
            "max_tokens": 1024,
            "system": "You are a concise article summarizer. Always respond with valid JSON only.",
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let contentArray = json["content"] as? [[String: Any]],
                  let textBlock = contentArray.first(where: { ($0["type"] as? String) == "text" }),
                  let text = textBlock["text"] as? String,
                  let textData = text.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(SummaryResult.self, from: textData)
        } catch {
            return nil
        }
    }

    // MARK: - OpenAI

    private static func summarizeWithOpenAI(apiKey: String, url: String, title: String?, userNotes: String?) async -> SummaryResult? {
        guard let content = await extractContent(from: url), !content.isEmpty else { return nil }

        let prompt = buildPrompt(content: content, title: title, url: url, userNotes: userNotes)
        let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 25

        let body: [String: Any] = [
            "model": "gpt-4o",
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": "You are a concise article summarizer. Always respond with valid JSON only."],
                ["role": "user", "content": prompt]
            ]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String,
                  let textData = text.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(SummaryResult.self, from: textData)
        } catch {
            return nil
        }
    }
}
