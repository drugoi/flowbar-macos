import Foundation

enum URLValidationError: LocalizedError {
    case invalidURL
    case unsupportedHost
    case missingVideoId

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .unsupportedHost:
            return "Only youtube.com and youtu.be URLs are supported."
        case .missingVideoId:
            return "Missing or invalid YouTube video ID."
        }
    }
}

struct ValidatedURL: Equatable {
    let canonicalURL: URL
    let videoId: String
}

enum URLValidator {
    private static let allowedHosts: Set<String> = [
        "youtube.com",
        "www.youtube.com",
        "youtu.be"
    ]

    static func validate(_ raw: String) -> Result<ValidatedURL, URLValidationError> {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return .failure(.invalidURL)
        }
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            return .failure(.unsupportedHost)
        }

        if host == "youtu.be" {
            let videoId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !videoId.isEmpty else { return .failure(.missingVideoId) }
            return .success(ValidatedURL(canonicalURL: canonicalShortURL(videoId: videoId), videoId: videoId))
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.invalidURL)
        }
        let queryItems = components.queryItems ?? []
        let videoId = queryItems.first(where: { $0.name == "v" })?.value ?? ""
        guard !videoId.isEmpty else { return .failure(.missingVideoId) }

        return .success(ValidatedURL(canonicalURL: canonicalWatchURL(videoId: videoId), videoId: videoId))
    }

    private static func canonicalWatchURL(videoId: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }

    private static func canonicalShortURL(videoId: String) -> URL {
        URL(string: "https://youtu.be/\(videoId)")!
    }
}
