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
        let id = UUID()
        let track: Track
        let sharedCache: AACRangeCache?
        let continuation: CheckedContinuation<URL, Error>
        let onStart: @MainActor () -> Void
    }

    private var activeTask: Task<URL, Error>?
    private var activeRequestId: UUID?
    private var preparationTasks: [UUID: Task<Void, Never>] = [:]
    private var queue: [DownloadRequest] = []
    private var resumableDownload: (trackID: UUID, cache: AACRangeCache)?

    func startPreparation(for trackId: UUID, operation: @escaping @MainActor () async -> Void) {
        guard preparationTasks[trackId] == nil else { return }
        preparationTasks[trackId] = Task {
            defer { preparationTasks.removeValue(forKey: trackId) }
            await operation()
        }
    }

    func cancelPreparation(for trackId: UUID) -> Bool {
        guard let task = preparationTasks[trackId] else { return false }
        task.cancel()
        return true
    }

    func isPreparing(trackId: UUID) -> Bool {
        preparationTasks[trackId] != nil
    }

    func resumableCache(for trackID: UUID) -> AACRangeCache? {
        guard resumableDownload?.trackID == trackID else { return nil }
        return resumableDownload?.cache
    }

    func discardResumableCache(for trackID: UUID) {
        if resumableDownload?.trackID == trackID { resumableDownload = nil }
    }

    func enqueueDownload(for track: Track, sharedCache: AACRangeCache? = nil,
                         onStart: @escaping @MainActor () -> Void) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let request = DownloadRequest(track: track, sharedCache: sharedCache, continuation: continuation, onStart: onStart)
            queue.append(request)
            queuedTrackIds = queue.map { $0.track.id }
            processQueue()
        }
    }

    func cancelActiveDownload() {
        activeTask?.cancel()
    }

    func cancelAllDownloads() {
        activeTask?.cancel()
        preparationTasks.values.forEach { $0.cancel() }
        let requests = queue
        queue = []
        queuedTrackIds = []
        resumableDownload = nil
        requests.forEach { $0.continuation.resume(throwing: DownloadError.cancelled) }
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
        activeRequestId = request.id
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

        if let cache = request.sharedCache {
            resumableDownload = (request.track.id, cache)
        }
        let reportProgress: @Sendable (Double?) -> Void = { [weak self, id = request.id] value in
            Task { @MainActor in
                guard self?.activeRequestId == id else { return }
                self?.progress = value
            }
        }
        let task = Task { () throws -> URL in
            if let cache = request.sharedCache {
                do {
                    try await cache.fill(destination: destination) { reportProgress($0) }
                    discardResumableCache(for: request.track.id)
                    return destination
                } catch AACRangeError.invalidResponse {
                    try Task.checkCancellation()
                    discardResumableCache(for: request.track.id)
                    DiagnosticsLogger.shared.log(level: "warning", message: "AAC source stopped serving byte ranges. Retrying as an offline download.")
                }
            }
            try await YtDlpClient().downloadAudio(url: request.track.sourceURL, destinationURL: destination, progress: reportProgress)
            try Task.checkCancellation()
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
                let failure = task.isCancelled ? DownloadError.cancelled : DownloadError.failed(error.localizedDescription)
                finishActiveDownload(request, result: .failure(failure))
            }
        }
    }

    private func finishActiveDownload(_ request: DownloadRequest, result: Result<URL, Error>) {
        activeTask = nil
        activeRequestId = nil
        activeTrackId = nil
        progress = nil
        request.continuation.resume(with: result)
        processQueue()
    }
}
