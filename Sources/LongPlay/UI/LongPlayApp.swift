import AppKit
import SwiftUI

@main
struct LongPlayMain {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        let isUITestRun = env["XCTestConfigurationFilePath"] != nil
        if isUITestRun || env["UITESTING"] == "1" || ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            NSApplication.shared.setActivationPolicy(.regular)
            NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            LongPlayUITestApp.main()
        } else {
            LongPlayApp.main()
        }
    }
}

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

struct LongPlayUITestApp: App {
    @NSApplicationDelegateAdaptor(UITestAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class UITestAppDelegate: NSObject, NSApplicationDelegate {
    private let libraryStore = LibraryStore()
    private let playbackController = PlaybackController()
    private let downloadManager = DownloadManager()
    private var window: NSWindow?

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let rootView = MenuBarContentView(
            libraryStore: libraryStore,
            playbackController: playbackController,
            downloadManager: downloadManager
        )
        .frame(width: 420)
        .frame(maxHeight: 720)
        .accessibilityIdentifier("LongPlayMainWindow")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 720),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "LongPlay"
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        self.window = window
    }
}
