import XCTest
@testable import FlowBar

final class TrackActionTests: XCTestCase {
    @MainActor
    func testCancellingPreparationCancelsItsTask() async {
        let manager = DownloadManager()
        let trackId = UUID()
        let started = expectation(description: "Preparing")
        let cancelled = expectation(description: "Preparation cancelled")

        manager.startPreparation(for: trackId) {
            started.fulfill()
            do {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                XCTFail("Preparation completed after cancellation")
            } catch is CancellationError {
                cancelled.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        await fulfillment(of: [started], timeout: 1)

        XCTAssertTrue(manager.cancelPreparation(for: trackId))
        XCTAssertFalse(manager.cancelPreparation(for: UUID()))
        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testDeletingLastTrackUsingCachedFileRemovesAudio() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let caches = root.appendingPathComponent("Caches")
        AppPaths.overrideApplicationSupportDirectory = root.appendingPathComponent("Library")
        AppPaths.overrideCachesDirectory = caches
        defer {
            AppPaths.overrideApplicationSupportDirectory = nil
            AppPaths.overrideCachesDirectory = nil
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        let audio = caches.appendingPathComponent("track.m4a")
        try Data([42]).write(to: audio)
        let store = LibraryStore()
        let source = try XCTUnwrap(URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw"))
        var first = Track.makeNew(sourceURL: source, videoId: "jNQXAC9IVRw", displayName: "First")
        first.downloadState = .downloaded
        first.localFilePath = audio.path
        var second = first
        second.id = UUID()
        store.addToLibrary(first)
        store.addToLibrary(second)

        store.removeTrack(first)
        XCTAssertNil(store.track(withId: first.id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: audio.path))

        store.removeTrack(second)
        XCTAssertNil(store.track(withId: second.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audio.path))
    }
}
