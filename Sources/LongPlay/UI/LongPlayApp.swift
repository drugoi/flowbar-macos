import SwiftUI

@main
struct LongPlayApp: App {
    @StateObject private var libraryStore = LibraryStore()
    @StateObject private var playbackController = PlaybackController()
    @StateObject private var downloadManager = DownloadManager()

    var body: some Scene {
        MenuBarExtra("LongPlay", systemImage: "music.note") {
            MenuBarContentView(
                libraryStore: libraryStore,
                playbackController: playbackController,
                downloadManager: downloadManager
            )
            .frame(width: 360)
        }
        .menuBarExtraStyle(.window)
    }
}
