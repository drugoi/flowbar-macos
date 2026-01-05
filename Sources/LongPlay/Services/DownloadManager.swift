import Foundation
import Combine

enum DownloadError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        "Download is not implemented yet."
    }
}

final class DownloadManager: ObservableObject {
    @Published private(set) var activeTrackId: UUID?
    @Published private(set) var progress: Double?

    func startDownload(for track: Track) async throws -> URL {
        activeTrackId = track.id
        progress = nil
        throw DownloadError.unsupported
    }

    func cancelDownload() {
        activeTrackId = nil
        progress = nil
    }
}
