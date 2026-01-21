import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var playbackController: PlaybackController
    @ObservedObject var downloadManager: DownloadManager

    var body: some View {
        let status = statusState
        ZStack {
            Image("TrayIcon")
                .renderingMode(.template)
            if let badgeSymbol = status.badgeSymbol {
                Image(systemName: badgeSymbol)
                    .font(.system(size: 7, weight: .bold))
                    .symbolRenderingMode(.hierarchical)
                    .offset(x: 7, y: 6)
            }
        }
        .accessibilityLabel("LongPlay: \(status.label)")
        .accessibilityIdentifier("LongPlayStatusItem")
    }

    private var statusState: MenuBarStatusState {
        switch playbackController.state {
        case .playing:
            return .playing
        case .paused:
            return .paused
        case .error:
            return .error
        case .idle:
            if isDownloading {
                return .downloading
            }
            if isResolving {
                return .resolving
            }
            if hasFailedDownload {
                return .error
            }
            return .idle
        }
    }

    private var isDownloading: Bool {
        if downloadManager.activeTrackId != nil {
            return true
        }
        return libraryStore.library.userLibrary.contains { $0.downloadState == .downloading }
    }

    private var isResolving: Bool {
        libraryStore.library.userLibrary.contains { $0.downloadState == .resolving }
    }

    private var hasFailedDownload: Bool {
        libraryStore.library.userLibrary.contains { $0.downloadState == .failed }
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
