import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var playbackController: PlaybackController
    @ObservedObject var downloadManager: DownloadManager

    var body: some View {
        Image("TrayIcon")
            .renderingMode(.template)
            .accessibilityLabel("LongPlay")
            .accessibilityIdentifier("LongPlayStatusItem")
    }
}
