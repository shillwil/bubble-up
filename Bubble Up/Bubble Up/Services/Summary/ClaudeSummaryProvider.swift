import Foundation

/// BYOK Claude provider — calls Anthropic Messages API directly.
/// Default for book summaries using Claude Sonnet 4.6.
struct ClaudeSummaryProvider: SummaryProvider {
    let providerName = "Claude"
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func generateLinkSummary(content: String, title: String?, url: String, userNotes: String?) async throws -> SummaryResult {
        let prompt = buildLinkSummaryPrompt(content: content, title: title, url: url, userNotes: userNotes)
        let responseText = try await callClaudeAPI(
            model: "claude-sonnet-4-6-20250514",
            systemPrompt: "You are a concise article summarizer. Always respond with valid JSON only.",
            userPrompt: prompt
        )
        return try parseSummaryResult(from: responseText)
    }

    func generateBookSummary(title: String, author: String?, length: SummaryLength) async throws -> BookSummaryResult {
        let prompt = buildBookSummaryPrompt(title: title, author: author, length: length)
        let responseText = try await callClaudeAPI(
            model: Config.defaultBookSummaryModel,
            systemPrompt: "You are a book summary expert who creates Blinkist-style breakdowns. Always respond with valid JSON only.",
            userPrompt: prompt
        )
        return try parseBookSummaryResult(from: responseText)
    }

    // MARK: - API Call

    private func callClaudeAPI(model: String, systemPrompt: String, userPrompt: String) async throws -> String {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": [
                ["role": "user", "content": userPrompt]
            ]
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SummaryProviderError.networkError(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200:
            break
        case 429:
            throw SummaryProviderError.rateLimitExceeded(retryAfter: nil)
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummaryProviderError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        // Parse Claude Messages API response
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let textBlock = contentArray.first(where: { ($0["type"] as? String) == "text" }),
              let text = textBlock["text"] as? String else {
            throw SummaryProviderError.decodingFailed
        }

        return text
    }

    // MARK: - Prompts

    private func buildLinkSummaryPrompt(content: String, title: String?, url: String, userNotes: String?) -> String {
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

    private func buildBookSummaryPrompt(title: String, author: String?, length: SummaryLength) -> String {
        let authorText = author.map { " by \($0)" } ?? ""

        return """
        Generate a comprehensive book summary for "\(title)"\(authorText).

        Return your response as a JSON object with this exact structure:
        {
            "summary": "A comprehensive overview of the book's main thesis",
            "elevatorPitch": "One sentence elevator pitch",
            "pages": [
                {"pageNumber": 1, "title": "Key Idea Title", "content": "2-4 paragraphs..."},
                {"pageNumber": 2, "title": "Another Key Idea", "content": "..."}
            ]
        }

        Rules:
        - The summary should be 2-3 sentences
        - The elevator pitch should be one compelling sentence
        - Each page should have 2-4 rich paragraphs of substantive content (300-500 words per page)
        - Include \(length == .short ? "3-5" : "6-8") pages covering the book's key ideas
        - Write in an engaging, accessible style
        - Return ONLY the JSON object, no other text
        """
    }

    // MARK: - Parsing

    private func parseSummaryResult(from text: String) throws -> SummaryResult {
        guard let data = text.data(using: .utf8) else { throw SummaryProviderError.decodingFailed }
        return try JSONDecoder().decode(SummaryResult.self, from: data)
    }

    private func parseBookSummaryResult(from text: String) throws -> BookSummaryResult {
        guard let data = text.data(using: .utf8) else { throw SummaryProviderError.decodingFailed }
        return try JSONDecoder().decode(BookSummaryResult.self, from: data)
    }
}
