import Foundation
import Supabase

/// F&F summary provider — routes through Supabase Edge Functions.
struct SupabaseSummaryProvider: SummaryProvider {
    let providerName = "Supabase (F&F)"

    func generateLinkSummary(content: String, title: String?, url: String, userNotes: String?) async throws -> SummaryResult {
        var body: [String: String] = [
            "url": url,
            "title": title ?? "",
            "content": String(content.prefix(8000))
        ]
        if let notes = userNotes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["userNotes"] = notes
        }

        let result: SummaryResult = try await SupabaseClientProvider.shared.functions.invoke(
            "summarize-link",
            options: .init(body: body)
        )

        return result
    }

    func generateBookSummary(title: String, author: String?, length: SummaryLength) async throws -> BookSummaryResult {
        var body: [String: String] = [
            "bookTitle": title,
            "summaryLength": length.rawValue
        ]
        if let author { body["author"] = author }

        let result: BookSummaryResult = try await SupabaseClientProvider.shared.functions.invoke(
            "summarize-book",
            options: .init(body: body)
        )

        return result
    }
}
