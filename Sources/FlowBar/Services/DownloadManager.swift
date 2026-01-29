import Foundation
import Combine

enum DownloadError: LocalizedError {
    case failed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .failed(let message):
            return message
        case .cancelled:
            return "Download cancelled."
        }
    }
}

@MainActor
final class DownloadManager: ObservableObject, @unchecked Sendable {
    @Published private(set) var activeTrackId: UUID?
    @Published private(set) var queuedTrackIds: [UUID] = []
    @Published private(set) var progress: Double?

    private struct DownloadRequest {
        let track: Track
        let continuation: CheckedContinuation<URL, Error>
        let onStart: @MainActor () -> Void
    }

    private var activeTask: Task<URL, Error>?
    private var queue: [DownloadRequest] = []

    func enqueueDownload(for track: Track, onStart: @escaping @MainActor () -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let request = DownloadRequest(track: track, continuation: continuation, onStart: onStart)
            queue.append(request)
            queuedTrackIds = queue.map { $0.track.id }
            processQueue()
        }
    }

    func cancelActiveDownload() {
        activeTask?.cancel()
    }

    func removeFromQueue(trackId: UUID) {
        if let index = queue.firstIndex(where: { $0.track.id == trackId }) {
            let request = queue.remove(at: index)
            queuedTrackIds = queue.map { $0.track.id }
            request.continuation.resume(throwing: DownloadError.cancelled)
        }
    }

    func isQueued(trackId: UUID) -> Bool {
        queuedTrackIds.contains(trackId)
    }

    func queuePosition(for trackId: UUID) -> Int? {
        queuedTrackIds.firstIndex(of: trackId).map { $0 + 1 }
    }

    private func processQueue() {
        guard activeTask == nil else { return }
        guard !queue.isEmpty else { return }

        let request = queue.removeFirst()
        queuedTrackIds = queue.map { $0.track.id }
        startDownload(request)
    }

    private func startDownload(_ request: DownloadRequest) {
        activeTrackId = request.track.id
        progress = 0
        request.onStart()

        let destination: URL
        do {
            let cachesDirectory = try AppPaths.cachesDirectory()
            destination = cachesDirectory.appendingPathComponent("\(request.track.videoId).m4a")
        } catch {
            finishActiveDownload(
                request,
                result: .failure(
                    DownloadError.failed("Unable to access cache directory: \(error.localizedDescription)")
                )
            )
            return
        }

        let client = YtDlpClient()
        let task = Task { () throws -> URL in
            try await client.downloadAudio(url: request.track.sourceURL, destinationURL: destination) { [weak self] value in
                Task { @MainActor in
                    self?.progress = value
                }
            }
            return destination
        }
        activeTask = task

        Task {
            do {
                let url = try await task.value
                finishActiveDownload(request, result: .success(url))
            } catch is CancellationError {
                finishActiveDownload(request, result: .failure(DownloadError.cancelled))
            } catch {
                finishActiveDownload(request, result: .failure(DownloadError.failed(error.localizedDescription)))
            }
        }
    }

    private func finishActiveDownload(_ request: DownloadRequest, result: Result<URL, Error>) {
        activeTask = nil
        activeTrackId = nil
        progress = nil
        request.continuation.resume(with: result)
        processQueue()
    }
}
