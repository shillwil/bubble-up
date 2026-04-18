import Foundation

/// BYOK Gemini provider — calls Google's Gemini API directly.
/// Default for link summaries using Gemini 3.1 Flash.
struct GeminiSummaryProvider: SummaryProvider {
    let providerName = "Gemini"
    private let apiKey: String
    private let session: URLSession

    init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    func generateLinkSummary(content: String, title: String?, url: String) async throws -> SummaryResult {
        let model = Config.defaultLinkSummaryModel
        let prompt = buildLinkSummaryPrompt(content: content, title: title, url: url)

        let responseText = try await callGeminiAPI(model: model, prompt: prompt)
        return try parseSummaryResult(from: responseText)
    }

    func generateBookSummary(title: String, author: String?, length: SummaryLength) async throws -> BookSummaryResult {
        let model = Config.defaultLinkSummaryModel // Use flash for BYOK book summaries too
        let prompt = buildBookSummaryPrompt(title: title, author: author, length: length)

        let responseText = try await callGeminiAPI(model: model, prompt: prompt)
        return try parseBookSummaryResult(from: responseText)
    }

    // MARK: - API Call

    private func callGeminiAPI(model: String, prompt: String) async throws -> String {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 30

        let body: [String: Any] = [
            "contents": [
                ["parts": [["text": prompt]]]
            ],
            "generationConfig": [
                "responseMimeType": "application/json"
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

        // Parse Gemini response structure
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw SummaryProviderError.decodingFailed
        }

        return text
    }

    // MARK: - Prompt Building

    private func buildLinkSummaryPrompt(content: String, title: String?, url: String) -> String {
        """
        Summarize the following article. Return your response as a JSON object with this exact structure:
        {
            "summary": "A 1-2 sentence summary of the article",
            "bullets": ["bullet point 1", "bullet point 2", "bullet point 3"],
            "estimatedReadTime": 5
        }

        Rules:
        - The summary should be 1-2 concise sentences capturing the main idea
        - Provide exactly 3 bullet points, each one sentence, highlighting key insights
        - estimatedReadTime is in minutes, estimate based on article length
        - Return ONLY the JSON object, no other text

        Title: \(title ?? "Unknown")
        URL: \(url)

        Article content:
        \(String(content.prefix(8000)))
        """
    }

    private func buildBookSummaryPrompt(title: String, author: String?, length: SummaryLength) -> String {
        let authorText = author.map { " by \($0)" } ?? ""
        let lengthInstruction = length == .short
            ? "Provide a short summary with an elevator pitch and 5-15 bullet points."
            : "Provide a comprehensive summary broken into 5-8 key idea pages."

        return """
        Generate a book summary for "\(title)"\(authorText). \(lengthInstruction)

        Return your response as a JSON object with this exact structure:
        {
            "summary": "A comprehensive overview of the book's main thesis and contribution",
            "elevatorPitch": "One sentence elevator pitch of the book",
            "pages": [
                {"pageNumber": 1, "title": "Key Idea Title", "content": "2-4 paragraphs explaining this key idea..."},
                {"pageNumber": 2, "title": "Another Key Idea", "content": "..."}
            ]
        }

        Rules:
        - The summary should be 2-3 sentences
        - The elevator pitch should be exactly one compelling sentence
        - Each page should have 2-4 paragraphs of substantive content
        - \(length == .short ? "Include 3-5 pages" : "Include 5-8 pages")
        - Return ONLY the JSON object, no other text
        """
    }

    // MARK: - Response Parsing

    private func parseSummaryResult(from text: String) throws -> SummaryResult {
        guard let data = text.data(using: .utf8) else {
            throw SummaryProviderError.decodingFailed
        }
        do {
            return try JSONDecoder().decode(SummaryResult.self, from: data)
        } catch {
            throw SummaryProviderError.decodingFailed
        }
    }

    private func parseBookSummaryResult(from text: String) throws -> BookSummaryResult {
        guard let data = text.data(using: .utf8) else {
            throw SummaryProviderError.decodingFailed
        }
        do {
            return try JSONDecoder().decode(BookSummaryResult.self, from: data)
        } catch {
            throw SummaryProviderError.decodingFailed
        }
    }
}
