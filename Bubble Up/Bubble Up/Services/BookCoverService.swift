import Foundation

struct BookCoverService {

    /// Fetches a book cover image URL from the Open Library API.
    /// Returns nil if no cover is found. Best-effort, fails silently.
    func fetchCoverURL(title: String, author: String?) async -> URL? {
        var queryItems = [URLQueryItem(name: "title", value: title), URLQueryItem(name: "limit", value: "1"), URLQueryItem(name: "fields", value: "cover_i")]
        if let author, !author.isEmpty {
            queryItems.append(URLQueryItem(name: "author", value: author))
        }

        var components = URLComponents(string: "https://openlibrary.org/search.json")!
        components.queryItems = queryItems

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            // Parse JSON: { "docs": [{ "cover_i": 12345 }] }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let docs = json["docs"] as? [[String: Any]],
                  let firstDoc = docs.first,
                  let coverID = firstDoc["cover_i"] as? Int else {
                return nil
            }
            return URL(string: "https://covers.openlibrary.org/b/id/\(coverID)-L.jpg")
        } catch {
            print("Book cover fetch failed: \(error)")
            return nil
        }
    }
}
