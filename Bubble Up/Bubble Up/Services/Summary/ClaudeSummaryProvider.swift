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

    func generateLinkSummary(content: String, title: String?, url: String) async throws -> SummaryResult {
        // Use tool calling with a forced schema so Claude can't silently drop
        // the `title` field (it did this consistently with plain JSON prompts).
        let prompt = buildLinkSummaryPrompt(content: content, title: title, url: url)
        let input = try await callClaudeToolAPI(
            model: "claude-sonnet-4-6-20250514",
            systemPrompt: "You are a concise article summarizer. Call the record_summary tool with your analysis.",
            userPrompt: prompt,
            tool: Self.linkSummaryTool,
            toolName: "record_summary"
        )
        return try parseSummaryResult(fromToolInput: input)
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

    // MARK: - Tool schema

    private static let linkSummaryTool: [String: Any] = [
        "name": "record_summary",
        "description": "Records the article/post summary with a concise title.",
        "input_schema": [
            "type": "object",
            "properties": [
                "title": [
                    "type": "string",
                    "description": "A concise 3-8 word title capturing the subject. MUST always be present."
                ],
                "summary": [
                    "type": "string",
                    "description": "A 1-2 sentence summary of the main idea."
                ],
                "bullets": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": "Exactly 3 single-sentence bullet points with key insights."
                ],
                "estimatedReadTime": [
                    "type": "integer",
                    "description": "Estimated read time in minutes."
                ]
            ],
            "required": ["title", "summary", "bullets", "estimatedReadTime"]
        ]
    ]

    // MARK: - API Calls

    /// Tool-calling variant that forces Claude to produce a schema-conforming
    /// JSON object (returned as the tool's `input` field).
    private func callClaudeToolAPI(
        model: String,
        systemPrompt: String,
        userPrompt: String,
        tool: [String: Any],
        toolName: String
    ) async throws -> [String: Any] {
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
            "tools": [tool],
            "tool_choice": ["type": "tool", "name": toolName],
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
        case 200: break
        case 429: throw SummaryProviderError.rateLimitExceeded(retryAfter: nil)
        default:
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SummaryProviderError.apiError(statusCode: httpResponse.statusCode, message: message)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let toolUse = contentArray.first(where: { ($0["type"] as? String) == "tool_use" }),
              let input = toolUse["input"] as? [String: Any] else {
            print("⚠️ [Claude] tool_use block missing — raw JSON: \(String(data: data, encoding: .utf8)?.prefix(400) ?? "<nil>")")
            throw SummaryProviderError.decodingFailed
        }

        return input
    }

    /// Plain-text variant used for book summaries (no schema forcing needed).
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

    private func buildLinkSummaryPrompt(content: String, title: String?, url: String) -> String {
        """
        Summarize the following article. Return your response as a JSON object with this exact structure:
        {
            "title": "Concise 3-8 word title",
            "summary": "A 1-2 sentence summary of the article",
            "bullets": ["bullet point 1", "bullet point 2", "bullet point 3"],
            "estimatedReadTime": 5
        }

        Rules:
        - title is a concise, descriptive 3-8 word title capturing the article's subject. If the Title below is descriptive, you may return a lightly shortened version of it; otherwise generate one from the content.
        - The summary should be 1-2 concise sentences capturing the main idea
        - Provide exactly 3 bullet points, each one sentence, highlighting key insights
        - estimatedReadTime is in minutes
        - Return ONLY the JSON object, no other text

        Title: \(title ?? "Unknown")
        URL: \(url)

        Article content:
        \(String(content.prefix(8000)))
        """
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

    /// Decodes a `SummaryResult` directly from Claude's tool_use input object
    /// (no JSON round-trip — the shape is already dictionary form).
    private func parseSummaryResult(fromToolInput input: [String: Any]) throws -> SummaryResult {
        let data = try JSONSerialization.data(withJSONObject: input)
        let result = try JSONDecoder().decode(SummaryResult.self, from: data)
        if result.title == nil || result.title?.isEmpty == true {
            print("⚠️ [Claude] tool returned empty title — input: \(input)")
        }
        return result
    }

    private func parseBookSummaryResult(from text: String) throws -> BookSummaryResult {
        guard let data = text.data(using: .utf8) else { throw SummaryProviderError.decodingFailed }
        return try JSONDecoder().decode(BookSummaryResult.self, from: data)
    }
}
