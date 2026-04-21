import Foundation

/// Structured representation of a social post (tweet or reddit post) used by
/// both the content processors (which encode it into `rawContent`) and the
/// detail view reader cards (which decode it back for typed rendering).
///
/// Keeping the serialization format centralized here avoids the reader and
/// processors drifting apart on field names or section ordering.
struct SocialPostContent: Sendable {
    enum Platform: String, Sendable { case twitter, reddit }

    struct Comment: Sendable {
        let author: String   // bare handle, no "u/" prefix
        let body: String
    }

    /// A moderator- or bot-posted thread summary (typically stickied with
    /// "TL;DR" framing). Rendered prominently above the top comments.
    struct DiscussionSummary: Sendable {
        let author: String   // bare handle (e.g. "AutoModerator", "autotldr")
        let body: String
    }

    let platform: Platform
    let authorDisplayName: String?
    let authorHandle: String?            // "@alice" for twitter, "u/alice" for reddit
    let subreddit: String?               // "r/swift"; nil for twitter
    let body: String                     // tweet text or reddit selftext
    let discussionSummary: DiscussionSummary?  // reddit-only; nil when absent
    let topComments: [Comment]           // empty for twitter
    let mediaCount: Int                  // photos + video (if any)
    let hasVideo: Bool
}

enum SocialPostCodec {

    // MARK: - Section markers
    //
    // These prefixes are what the codec writes and reads. They're chosen to
    // double as human-readable prose so the AI summarizer can ingest the same
    // text without any additional preprocessing.
    private enum Marker {
        static let tweetBy = "Tweet by "
        static let subreddit = "Subreddit: "
        static let postedBy = "Posted by "
        static let postBody = "Post body:\n"
        static let topComments = "Top comments:\n"
        static let threadSummaryOpen = "Thread summary (by u/"
        static let threadSummaryClose = "):\n"
        static let imagesPrefix = "Contains "           // "Contains N image(s)"
        static let imagesSuffix = "image"
        static let videoLine = "Contains a video"
    }

    /// Ordered list used by the structural decoder. `videoLine` must precede
    /// `imagesPrefix` because both start with "Contains " — the scanner takes
    /// the first prefix match.
    private static let sectionMarkers: [String] = [
        Marker.tweetBy,
        Marker.subreddit,
        Marker.postedBy,
        Marker.postBody,
        Marker.threadSummaryOpen,
        Marker.topComments,
        Marker.videoLine,
        Marker.imagesPrefix
    ]

    // MARK: - Encode

    static func encode(_ post: SocialPostContent) -> String {
        var sections: [String] = []

        switch post.platform {
        case .twitter:
            if let name = post.authorDisplayName, let handle = post.authorHandle {
                sections.append("\(Marker.tweetBy)\(name) (\(handle))")
            } else if let handle = post.authorHandle {
                sections.append("\(Marker.tweetBy)\(handle)")
            } else if let name = post.authorDisplayName {
                sections.append("\(Marker.tweetBy)\(name)")
            }
            if !post.body.isEmpty { sections.append(post.body) }
            if post.mediaCount > 0 {
                sections.append("Contains \(post.mediaCount) \(Marker.imagesSuffix)\(post.mediaCount == 1 ? "" : "s")")
            }
            if post.hasVideo { sections.append(Marker.videoLine) }

        case .reddit:
            if let sub = post.subreddit { sections.append("\(Marker.subreddit)\(sub)") }
            if let handle = post.authorHandle { sections.append("\(Marker.postedBy)\(handle)") }
            if !post.body.isEmpty { sections.append("\(Marker.postBody)\(post.body)") }
            if let summary = post.discussionSummary {
                sections.append("\(Marker.threadSummaryOpen)\(summary.author)\(Marker.threadSummaryClose)\(summary.body)")
            }
            if !post.topComments.isEmpty {
                let joined = post.topComments
                    .map { "u/\($0.author): \($0.body)" }
                    .joined(separator: "\n\n")
                sections.append("\(Marker.topComments)\(joined)")
            }
        }

        return sections.joined(separator: "\n\n")
    }

    // MARK: - Decode

    static func decode(_ raw: String, platform: SocialPostContent.Platform) -> SocialPostContent? {
        guard !raw.isEmpty else { return nil }

        // A section boundary is either the very start of the string or the
        // position immediately after a "\n\n". Only boundaries whose text begins
        // with a known marker are treated as new sections — so marker-tagged
        // content can freely contain internal paragraph breaks without being
        // split across sections.
        let hits = findHits(in: raw)

        var authorDisplayName: String?
        var authorHandle: String?
        var subreddit: String?
        var body = ""
        var discussionSummary: SocialPostContent.DiscussionSummary?
        var topComments: [SocialPostContent.Comment] = []
        var mediaCount = 0
        var hasVideo = false

        for (i, hit) in hits.enumerated() {
            let sectionEnd = i + 1 < hits.count ? hits[i + 1].start : raw.endIndex
            let sectionSubstring = raw[hit.start..<sectionEnd]
            let trimmed = String(sectionSubstring).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix(hit.marker) else { continue }

            let content = String(trimmed.dropFirst(hit.marker.count))

            switch hit.marker {
            case Marker.tweetBy:
                // The attribution is the first line; any content after "\n\n" is
                // the tweet body (it lives in the same scanner section because it
                // doesn't start with a marker of its own).
                if let breakRange = content.range(of: "\n\n") {
                    let attribution = String(content[content.startIndex..<breakRange.lowerBound])
                    let rest = String(content[breakRange.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    (authorDisplayName, authorHandle) = parseTweetAttribution(attribution)
                    if !rest.isEmpty { body = rest }
                } else {
                    (authorDisplayName, authorHandle) = parseTweetAttribution(content)
                }

            case Marker.subreddit:
                subreddit = content

            case Marker.postedBy:
                authorHandle = content

            case Marker.postBody:
                body = content

            case Marker.threadSummaryOpen:
                // Content is `<author>):\n<body>` where the body may span many paragraphs.
                if let closeRange = content.range(of: Marker.threadSummaryClose) {
                    let author = String(content[content.startIndex..<closeRange.lowerBound])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let summaryBody = String(content[closeRange.upperBound...])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !author.isEmpty, !summaryBody.isEmpty {
                        discussionSummary = .init(author: author, body: summaryBody)
                    }
                }

            case Marker.topComments:
                topComments = parseComments(content)

            case Marker.videoLine:
                hasVideo = true

            case Marker.imagesPrefix:
                // Content is the digit run plus " image(s)" — we only need the count.
                let digits = content.prefix { $0.isNumber }
                if let count = Int(digits) { mediaCount += count }

            default:
                break
            }
        }

        return SocialPostContent(
            platform: platform,
            authorDisplayName: authorDisplayName,
            authorHandle: authorHandle,
            subreddit: subreddit,
            body: body,
            discussionSummary: discussionSummary,
            topComments: topComments,
            mediaCount: mediaCount,
            hasVideo: hasVideo
        )
    }

    // MARK: - Section scanning

    private struct Hit {
        let start: String.Index
        let marker: String
    }

    private static func findHits(in raw: String) -> [Hit] {
        var hits: [Hit] = []
        if let marker = matchedMarker(at: raw.startIndex, in: raw) {
            hits.append(.init(start: raw.startIndex, marker: marker))
        }
        var cursor = raw.startIndex
        while let br = raw.range(of: "\n\n", range: cursor..<raw.endIndex) {
            let after = br.upperBound
            if let marker = matchedMarker(at: after, in: raw) {
                hits.append(.init(start: after, marker: marker))
            }
            cursor = br.upperBound
        }
        return hits
    }

    private static func matchedMarker(at index: String.Index, in raw: String) -> String? {
        let tail = raw[index...]
        return sectionMarkers.first(where: { tail.hasPrefix($0) })
    }

    // MARK: - Attribution parsing

    /// Splits "Display Name (@handle)" into its parts. Falls back gracefully.
    private static func parseTweetAttribution(_ input: String) -> (displayName: String?, handle: String?) {
        guard let openParen = input.lastIndex(of: "(") else {
            return (input.isEmpty ? nil : input, nil)
        }
        let name = input[..<openParen].trimmingCharacters(in: .whitespacesAndNewlines)
        let handlePart = input[input.index(after: openParen)...]
            .trimmingCharacters(in: CharacterSet(charactersIn: "() "))
        return (name.isEmpty ? nil : name, handlePart.isEmpty ? nil : handlePart)
    }

    /// Parses a block of comments encoded as `u/author: body` entries separated
    /// by "\n\n". Comment bodies may themselves span multiple paragraphs, so we
    /// boundary-split on "\n\nu/" (the start of the next attribution) rather
    /// than on plain "\n\n".
    private static func parseComments(_ input: String) -> [SocialPostContent.Comment] {
        // Find every "\n\nu/" boundary; the start of each comment is either the
        // very beginning of the input or two characters past one of those ranges
        // (to skip the "\n\n" but keep the "u/").
        var boundaries: [String.Index] = [input.startIndex]
        var cursor = input.startIndex
        while let range = input.range(of: "\n\nu/", range: cursor..<input.endIndex) {
            boundaries.append(input.index(range.lowerBound, offsetBy: 2))
            cursor = range.upperBound
        }

        var comments: [SocialPostContent.Comment] = []
        for (i, start) in boundaries.enumerated() {
            let end = i + 1 < boundaries.count ? boundaries[i + 1] : input.endIndex
            let chunk = String(input[start..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard chunk.hasPrefix("u/"),
                  let colon = chunk.firstIndex(of: ":") else { continue }
            let authorStart = chunk.index(chunk.startIndex, offsetBy: 2)
            let author = String(chunk[authorStart..<colon])
            let body = String(chunk[chunk.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !author.isEmpty, !body.isEmpty else { continue }
            comments.append(.init(author: author, body: body))
        }
        return comments
    }
}
