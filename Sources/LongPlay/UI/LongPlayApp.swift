import SwiftUI

@main
struct LongPlayApp: App {
    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var playbackController = PlaybackController()
    @StateObject private var downloadManager = DownloadManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(
                libraryStore: libraryStore,
                playbackController: playbackController,
                downloadManager: downloadManager
            )
            .frame(width: 420)
            .frame(maxHeight: 720)
        } label: {
            MenuBarLabelView(
                libraryStore: libraryStore,
                playbackController: playbackController,
                downloadManager: downloadManager
            )
        }
        .menuBarExtraStyle(.window)
    }
}
