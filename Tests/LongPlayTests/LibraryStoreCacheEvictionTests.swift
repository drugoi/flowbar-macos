import XCTest
@testable import LongPlay

final class LibraryStoreCacheEvictionTests: XCTestCase {
    private var tempRootURL: URL?
    private var supportURL: URL?
    private var cachesURL: URL?

    override func setUp() {
        super.setUp()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("LongPlayTests-\(UUID().uuidString)", isDirectory: true)
        let support = root.appendingPathComponent("Support", isDirectory: true)
        let caches = root.appendingPathComponent("Caches", isDirectory: true)
        tempRootURL = root
        supportURL = support
        cachesURL = caches
        AppPaths.overrideApplicationSupportDirectory = support
        AppPaths.overrideCachesDirectory = caches
    }

    override func tearDown() {
        AppPaths.overrideApplicationSupportDirectory = nil
        AppPaths.overrideCachesDirectory = nil
        if let tempRootURL {
            try? FileManager.default.removeItem(at: tempRootURL)
        }
        super.tearDown()
    }

    func testEnforceCacheLimitEvictsLeastRecentlyPlayed() throws {
        let cachesURL = try XCTUnwrap(cachesURL)
        let supportURL = try XCTUnwrap(supportURL)
        try FileManager.default.createDirectory(at: cachesURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: supportURL, withIntermediateDirectories: true)

        let olderFileURL = cachesURL.appendingPathComponent("older.dat")
        let newerFileURL = cachesURL.appendingPathComponent("newer.dat")
        try Data(repeating: 0xA, count: 60).write(to: olderFileURL)
        try Data(repeating: 0xB, count: 60).write(to: newerFileURL)

        let now = Date()
        let older = now.addingTimeInterval(-3600)
        let olderTrack = Track(
            id: UUID(),
            sourceURL: URL(string: "https://example.com/older")!,
            videoId: "older",
            displayName: "Older",
            resolvedTitle: nil,
            durationSeconds: nil,
            metadataUnavailable: nil,
            addedAt: older,
            lastPlayedAt: older,
            playbackPositionSeconds: 0,
            downloadState: .downloaded,
            downloadProgress: nil,
            localFilePath: olderFileURL.path,
            fileSizeBytes: 60,
            lastError: nil
        )
        let newerTrack = Track(
            id: UUID(),
            sourceURL: URL(string: "https://example.com/newer")!,
            videoId: "newer",
            displayName: "Newer",
            resolvedTitle: nil,
            durationSeconds: nil,
            metadataUnavailable: nil,
            addedAt: now,
            lastPlayedAt: now,
            playbackPositionSeconds: 0,
            downloadState: .downloaded,
            downloadProgress: nil,
            localFilePath: newerFileURL.path,
            fileSizeBytes: 60,
            lastError: nil
        )

        let library = Library(
            schemaVersion: Library.currentSchemaVersion,
            userLibrary: [olderTrack, newerTrack],
            cacheLimitBytes: 100
        )
        try writeLibrary(library, to: supportURL)

        let store = LibraryStore()
        waitForCondition(timeout: 3) {
            let olderState = store.library.userLibrary.first(where: { $0.id == olderTrack.id })?.downloadState
            let newerState = store.library.userLibrary.first(where: { $0.id == newerTrack.id })?.downloadState
            let olderFileExists = FileManager.default.fileExists(atPath: olderFileURL.path)
            let newerFileExists = FileManager.default.fileExists(atPath: newerFileURL.path)
            return olderState == .notDownloaded
                && !olderFileExists
                && newerState == .downloaded
                && newerFileExists
                && store.cacheSizeBytes <= 100
        }
    }

    private func writeLibrary(_ library: Library, to supportURL: URL) throws {
        let url = supportURL.appendingPathComponent("library.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(library)
        try data.write(to: url, options: [.atomic])
    }

    private func waitForCondition(timeout: TimeInterval, condition: @escaping () -> Bool) {
        let expectation = expectation(description: "Condition met")
        let deadline = Date().addingTimeInterval(timeout)

        func poll() {
            if condition() {
                expectation.fulfill()
                return
            }
            if Date() >= deadline {
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }

        poll()
        wait(for: [expectation], timeout: timeout + 0.5)
    }
}
