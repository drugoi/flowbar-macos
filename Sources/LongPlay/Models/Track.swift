import Foundation

enum DownloadState: String, Codable {
    case notDownloaded
    case resolving
    case downloading
    case downloaded
    case failed
}

struct Track: Identifiable, Codable, Equatable {
    var id: UUID
    var sourceURL: URL
    var videoId: String
    var displayName: String
    var resolvedTitle: String?
    var durationSeconds: Double?
    var metadataError: String?
    var addedAt: Date
    var lastPlayedAt: Date?
    var playbackPositionSeconds: Double
    var downloadState: DownloadState
    var downloadProgress: Double?
    var localFilePath: String?
    var fileSizeBytes: Int64?
    var lastError: String?
}

extension Track {
    static func makeNew(sourceURL: URL, videoId: String, displayName: String) -> Track {
        Track(
            id: UUID(),
            sourceURL: sourceURL,
            videoId: videoId,
            displayName: displayName,
            resolvedTitle: nil,
            durationSeconds: nil,
            metadataError: nil,
            addedAt: Date(),
            lastPlayedAt: nil,
            playbackPositionSeconds: 0,
            downloadState: .notDownloaded,
            downloadProgress: nil,
            localFilePath: nil,
            fileSizeBytes: nil,
            lastError: nil
        )
    }
}
