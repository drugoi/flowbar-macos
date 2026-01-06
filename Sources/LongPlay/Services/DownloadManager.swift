import Foundation
import Combine

enum DownloadError: LocalizedError {
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class DownloadManager: ObservableObject, @unchecked Sendable {
    @Published private(set) var activeTrackId: UUID?
    @Published private(set) var progress: Double?

    private var activeTask: Task<URL, Error>?

    func startDownload(for track: Track) async throws -> URL {
        activeTrackId = track.id
        progress = 0

        let destination = try AppPaths.cachesDirectory()
            .appendingPathComponent("\(track.videoId).m4a")
        let client = YtDlpClient()

        let task = Task { () throws -> URL in
            try await client.downloadAudio(url: track.sourceURL, destinationURL: destination) { [weak self] value in
                Task { @MainActor in
                    self?.progress = value
                }
            }
            return destination
        }
        activeTask = task

        do {
            let url = try await task.value
            activeTrackId = nil
            progress = nil
            return url
        } catch {
            activeTrackId = nil
            progress = nil
            throw DownloadError.failed(error.localizedDescription)
        }
    }

    func cancelDownload() {
        activeTask?.cancel()
        activeTrackId = nil
        progress = nil
    }
}
