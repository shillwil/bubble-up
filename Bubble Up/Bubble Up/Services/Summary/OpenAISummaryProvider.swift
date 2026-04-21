import Foundation

/// BYOK OpenAI provider — calls OpenAI Chat Completions API directly.
struct OpenAISummaryProvider: SummaryProvider {
    let providerName = "OpenAI"
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func generateLinkSummary(content: String, title: String?, url: String) async throws -> SummaryResult {
        let prompt = buildLinkSummaryPrompt(content: content, title: title, url: url)
        let responseText = try await callOpenAI(
            model: "gpt-4o",
            systemPrompt: "You are a concise article summarizer. Always respond with valid JSON only.",
            userPrompt: prompt
        )
        return try parseSummaryResult(from: responseText)
    }

    func generateBookSummary(title: String, author: String?, length: SummaryLength) async throws -> BookSummaryResult {
        let prompt = buildBookSummaryPrompt(title: title, author: author, length: length)
        let responseText = try await callOpenAI(
            model: "gpt-4o",
            systemPrompt: "You are a book summary expert. Always respond with valid JSON only.",
            userPrompt: prompt
        )
        return try parseBookSummaryResult(from: responseText)
    }

    // MARK: - API Call

    private func callOpenAI(model: String, systemPrompt: String, userPrompt: String) async throws -> String {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 60

        let body: [String: Any] = [
            "model": model,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": systemPrompt],
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
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw SummaryProviderError.decodingFailed
        }

        return text
    }

    // MARK: - Prompts (shared format with other providers)

    private func buildLinkSummaryPrompt(content: String, title: String?, url: String) -> String {
        """
        Summarize the following article. Return a JSON object:
        {"title": "concise 3-8 word title", "summary": "1-2 sentences", "bullets": ["point 1", "point 2", "point 3"], "estimatedReadTime": 5}

        For "title": a concise, descriptive 3-8 word title that captures the article's subject. If a Title is provided below and is descriptive, you may return a lightly shortened version of it; otherwise generate one from the content.

        Title: \(title ?? "Unknown")
        URL: \(url)

        Content:
        \(String(content.prefix(8000)))
        """
    }

    private func buildBookSummaryPrompt(title: String, author: String?, length: SummaryLength) -> String {
        let authorText = author.map { " by \($0)" } ?? ""
        return """
        Generate a book summary for "\(title)"\(authorText). Return JSON:
        {"summary": "overview", "elevatorPitch": "one sentence", "pages": [{"pageNumber": 1, "title": "...", "content": "..."}]}
        Include \(length == .short ? "3-5" : "6-8") pages with 2-4 paragraphs each.
        """
    }

    private func parseSummaryResult(from text: String) throws -> SummaryResult {
        guard let data = text.data(using: .utf8) else { throw SummaryProviderError.decodingFailed }
        return try JSONDecoder().decode(SummaryResult.self, from: data)
    }

    private func parseBookSummaryResult(from text: String) throws -> BookSummaryResult {
        guard let data = text.data(using: .utf8) else { throw SummaryProviderError.decodingFailed }
        return try JSONDecoder().decode(BookSummaryResult.self, from: data)
    }
}
