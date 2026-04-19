import Foundation

/// Strategy protocol for AI summary generation.
/// Implementations exist for each AI provider (Gemini, Claude, OpenAI) and for Supabase Edge Functions (F&F).
protocol SummaryProvider: Sendable {
    var providerName: String { get }

    func generateLinkSummary(
        content: String,
        title: String?,
        url: String,
        userNotes: String?
    ) async throws -> SummaryResult

    func generateBookSummary(
        title: String,
        author: String?,
        length: SummaryLength
    ) async throws -> BookSummaryResult
}

extension SummaryProvider {
    func generateLinkSummary(content: String, title: String?, url: String) async throws -> SummaryResult {
        try await generateLinkSummary(content: content, title: title, url: url, userNotes: nil)
    }
}

// MARK: - Response DTOs

struct SummaryResult: Sendable, Codable {
    let summary: String
    let bullets: [String]
    let estimatedReadTime: Int?
}

struct BookSummaryResult: Sendable, Codable {
    let summary: String
    let elevatorPitch: String
    let pages: [BookPage]

    struct BookPage: Sendable, Codable {
        let pageNumber: Int
        let title: String
        let content: String
    }
}

// MARK: - Errors

enum SummaryProviderError: Error, LocalizedError {
    case invalidAPIKey
    case rateLimitExceeded(retryAfter: TimeInterval?)
    case apiError(statusCode: Int, message: String)
    case decodingFailed
    case networkError(Error)
    case contentTooShort

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey: return "Invalid API key"
        case .rateLimitExceeded: return "Rate limit exceeded. Please try again later."
        case .apiError(let code, let msg): return "API error (\(code)): \(msg)"
        case .decodingFailed: return "Failed to parse AI response"
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .contentTooShort: return "Content too short to summarize"
        }
    }
}
