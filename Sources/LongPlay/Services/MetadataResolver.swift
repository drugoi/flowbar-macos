import Foundation

enum MetadataResolveError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        "Metadata resolution is not implemented yet."
    }
}

struct ResolvedMetadata: Equatable {
    let title: String
    let durationSeconds: Double?
}

enum MetadataResolver {
    static func resolve(for url: URL) async throws -> ResolvedMetadata {
        throw MetadataResolveError.unsupported
    }
}
