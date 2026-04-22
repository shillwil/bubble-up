import Foundation
import Supabase

/// F&F summary provider — routes through Supabase Edge Functions.
///
/// Note: for AI-generated titles to land on items where the user didn't
/// supply one, the `summarize-link` Edge Function must also return a
/// `title` field in its JSON response. `SummaryResult.title` is optional,
/// so responses without it decode cleanly and just fall back to the URL-
/// derived title in `RequestScheduler.writeSummaryResult`.
struct SupabaseSummaryProvider: SummaryProvider {
    let providerName = "Supabase (F&F)"

    func generateLinkSummary(content: String, title: String?, url: String) async throws -> SummaryResult {
        let body: [String: String] = [
            "url": url,
            "title": title ?? "",
            "content": String(content.prefix(8000))
        ]

        let result: SummaryResult = try await SupabaseClientProvider.shared.functions.invoke(
            "summarize-link",
            options: .init(body: body)
        )

        if result.title == nil || result.title?.isEmpty == true {
            print("⚠️ [Supabase] no title field returned — edge function needs update to include a \"title\" key in its JSON response.")
        }
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
