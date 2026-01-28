import Foundation

enum URLValidationError: LocalizedError, Equatable {
    case invalidURL
    case unsupportedHost
    case missingVideoId
    case unsupportedScheme

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL."
        case .unsupportedHost:
            return "Only youtube.com and youtu.be URLs are supported."
        case .missingVideoId:
            return "Missing or invalid YouTube video ID."
        case .unsupportedScheme:
            return "URL must start with http:// or https://."
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
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            return .failure(.invalidURL)
        }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return .failure(.unsupportedScheme)
        }
        guard let host = url.host?.lowercased(), allowedHosts.contains(host) else {
            return .failure(.unsupportedHost)
        }

        if host == "youtu.be" {
            let pathId = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard isValidVideoId(pathId) else { return .failure(.missingVideoId) }
            return .success(ValidatedURL(canonicalURL: canonicalWatchURL(videoId: pathId), videoId: pathId))
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.invalidURL)
        }
        if let pathId = extractVideoIdFromPath(components.path) {
            return .success(ValidatedURL(canonicalURL: canonicalWatchURL(videoId: pathId), videoId: pathId))
        }
        let queryItems = components.queryItems ?? []
        let videoId = queryItems.first(where: { $0.name == "v" })?.value ?? ""
        guard isValidVideoId(videoId) else { return .failure(.missingVideoId) }

        return .success(ValidatedURL(canonicalURL: canonicalWatchURL(videoId: videoId), videoId: videoId))
    }

    private static func canonicalWatchURL(videoId: String) -> URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoId)")!
    }

    private static func canonicalShortURL(videoId: String) -> URL {
        URL(string: "https://youtu.be/\(videoId)")!
    }

    private static func isValidVideoId(_ value: String) -> Bool {
        let pattern = "^[A-Za-z0-9_-]{11}$"
        return value.range(of: pattern, options: .regularExpression) != nil
    }

    private static func extractVideoIdFromPath(_ path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = trimmed.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        let prefix = parts[0].lowercased()
        if prefix == "shorts" || prefix == "embed" {
            let candidate = String(parts[1])
            return isValidVideoId(candidate) ? candidate : nil
        }
        return nil
    }
}
