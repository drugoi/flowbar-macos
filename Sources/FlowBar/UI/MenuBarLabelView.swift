import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var playbackController: PlaybackController
    @ObservedObject var downloadManager: DownloadManager
    private let badgeOffset = CGSize(width: 7, height: 6)

    var body: some View {
        let status = statusState
        ZStack {
            Image("TrayIcon")
                .renderingMode(.template)
            if let badgeSymbol = status.badgeSymbol {
                Image(systemName: badgeSymbol)
                    .font(.system(size: 7, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .offset(x: badgeOffset.width, y: badgeOffset.height)
            }
        }
        .accessibilityLabel("FlowBar: \(status.label)")
        .accessibilityIdentifier("FlowBarStatusItem")
    }

    private var statusState: MenuBarStatusState {
        let downloadStatus = libraryDownloadStatus
        switch playbackController.state {
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .error:
            return .error
        case .idle:
            if downloadManager.activeTrackId != nil || downloadStatus.hasDownloading {
                return .downloading
            }
            if downloadStatus.hasResolving {
                return .resolving
            }
            if downloadStatus.hasFailed {
                return .error
            }
            return .idle
        }
    }

    private struct LibraryDownloadStatus {
        let hasDownloading: Bool
        let hasResolving: Bool
        let hasFailed: Bool
    }

    private var libraryDownloadStatus: LibraryDownloadStatus {
        var hasDownloading = false
        var hasResolving = false
        var hasFailed = false
        for track in libraryStore.library.userLibrary {
            switch track.downloadState {
            case .downloading:
                hasDownloading = true
            case .resolving:
                hasResolving = true
            case .failed:
                hasFailed = true
            default:
                break
            }
            if hasDownloading && hasResolving && hasFailed {
                break
            }
        }
        return LibraryDownloadStatus(
            hasDownloading: hasDownloading,
            hasResolving: hasResolving,
            hasFailed: hasFailed
        )
    }
}

private enum MenuBarStatusState {
    case idle
    case resolving
    case downloading
    case playing
    case paused
    case error

    var label: String {
        switch self {
        case .idle:
            return "Idle"
        case .resolving:
            return "Resolving"
        case .downloading:
            return "Downloading"
        case .playing:
            return "Playing"
        case .paused:
            return "Paused"
        case .error:
            return "Error"
        }
    }

    var badgeSymbol: String? {
        switch self {
        case .idle:
            return nil
        case .resolving:
            return "hourglass"
        case .downloading:
            return "arrow.down"
        case .playing:
            return "play.fill"
        case .paused:
            return "pause.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}
