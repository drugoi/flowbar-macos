import Foundation

enum MetadataResolveError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

struct ResolvedMetadata: Equatable {
    let title: String
    let durationSeconds: Double?
}

enum MetadataResolver {
    static func resolve(for url: URL) async throws -> ResolvedMetadata {
        do {
            let client = YtDlpClient()
            let result = try await client.resolveMetadata(url: url)
            return ResolvedMetadata(title: result.title, durationSeconds: result.durationSeconds)
        } catch {
            throw MetadataResolveError.failed(error.localizedDescription)
        }
    }
}
