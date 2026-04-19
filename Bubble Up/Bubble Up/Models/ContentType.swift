import Foundation

/// Content type classification for extensible content processing.
/// Maps MIME types and URL patterns to processing strategies.
enum ContentType: Sendable {
    case webArticle
    case youtube
    case pdf
    case wordDoc
    case epub
    case image
    case video
    case unknown

    static func from(mimeType: String?) -> ContentType {
        guard let mimeType else { return .unknown }
        switch mimeType {
        case "text/html":
            return .webArticle
        case "video/youtube":
            return .youtube
        case "application/pdf":
            return .pdf
        case "application/msword",
             "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
            return .wordDoc
        case "application/epub+zip":
            return .epub
        case _ where mimeType.hasPrefix("image/"):
            return .image
        case _ where mimeType.hasPrefix("video/"):
            return .video
        default:
            return .unknown
        }
    }

    static func from(url: URL) -> ContentType {
        let host = url.host?.lowercased() ?? ""
        let pathExtension = url.pathExtension.lowercased()

        // YouTube detection
        if host.contains("youtube.com") || host.contains("youtu.be") {
            return .youtube
        }

        // File extension detection
        switch pathExtension {
        case "pdf":
            return .pdf
        case "doc", "docx":
            return .wordDoc
        case "epub":
            return .epub
        case "jpg", "jpeg", "png", "gif", "heic", "webp":
            return .image
        case "mp4", "mov", "avi", "mkv":
            return .video
        default:
            return .webArticle
        }
    }

    var mimeType: String {
        switch self {
        case .webArticle: return "text/html"
        case .youtube: return "video/youtube"
        case .pdf: return "application/pdf"
        case .wordDoc: return "application/msword"
        case .epub: return "application/epub+zip"
        case .image: return "image/jpeg"
        case .video: return "video/mp4"
        case .unknown: return "application/octet-stream"
        }
    }
}
