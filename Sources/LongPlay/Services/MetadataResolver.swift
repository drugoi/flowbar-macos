import Foundation

enum MetadataResolveError: LocalizedError {
    case failed(String)
    case timeout

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        case .timeout:
            return "Metadata resolution timed out. Check your connection and try again."
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
            let result = try await withTimeout(seconds: 20) {
                try await client.resolveMetadata(url: url)
            }
            return ResolvedMetadata(title: result.title, durationSeconds: result.durationSeconds)
        } catch let error as MetadataResolveError {
            throw error
        } catch {
            throw MetadataResolveError.failed(error.localizedDescription)
        }
    }

    private static func withTimeout<T>(seconds: UInt64, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                throw MetadataResolveError.timeout
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
}
