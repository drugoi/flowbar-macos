import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var playbackController: PlaybackController
    @ObservedObject var downloadManager: DownloadManager

    var body: some View {
        Image(systemName: iconName)
    }

    private var iconName: String {
        if playbackController.state == .error {
            return "exclamationmark.triangle.fill"
        }
        if downloadManager.activeTrackId != nil {
            return "arrow.down.circle.fill"
        }
        if libraryStore.library.featured.contains(where: { $0.downloadState == .resolving })
            || libraryStore.library.userLibrary.contains(where: { $0.downloadState == .resolving }) {
            return "arrow.triangle.2.circlepath.circle.fill"
        }
        switch playbackController.state {
        case .playing:
            return "play.circle.fill"
        case .paused:
            return "pause.circle.fill"
        case .idle:
            return "music.note"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }
}
