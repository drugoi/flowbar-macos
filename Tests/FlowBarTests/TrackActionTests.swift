import XCTest
@testable import FlowBar

final class TrackActionTests: XCTestCase {
    func testAACRangeRequiresMatchingBoundariesAndTotal() {
        XCTAssertEqual(AACRangeCache.totalLength(in: "bytes 0-1/512", matching: 0..<2), 512)
        XCTAssertNil(AACRangeCache.totalLength(in: "bytes 1-2/512", matching: 0..<2))
        XCTAssertNil(AACRangeCache.totalLength(in: "bytes 0-1/1", matching: 0..<2))
        XCTAssertNil(AACRangeCache.totalLength(in: "bytes 0-1/*", matching: 0..<2))
    }

    func testFragmentedAACIndexUsesOffsetsRelativeToTheEndOfSIDX() throws {
        func bytes(_ value: UInt32) -> [UInt8] {
            [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
             UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
        }
        let initBoxes = Data(bytes(8) + Array("ftyp".utf8) + bytes(8) + Array("moov".utf8))
        var data = initBoxes + Data(bytes(56) + Array("sidx".utf8))
        for field: UInt32 in [0, 1, 1_000, 0, 5, 2, 20, 1_250, 0, 30, 750, 0] {
            data.append(contentsOf: bytes(field))
        }
        let index = try XCTUnwrap(AACFragmentIndex(data: data, length: 127))
        XCTAssertEqual(index.initialization, 0..<16)
        XCTAssertEqual(index.segments.map(\.bytes), [77..<97, 97..<127])
        XCTAssertEqual(index.segments.map(\.duration), [1.25, 0.75])
        XCTAssertNil(AACFragmentIndex(data: data, length: 126))
    }

    func testSimultaneousPlaybackAndDownloadReuseAACBlocks() async throws {
        let source = Data((0..<25).map(UInt8.init))
        let requests = AACRequestRecorder(source: source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try AACRangeCache(length: 25, directory: directory, blockSize: 8) { range in
            try await requests.fetch(range)
        }
        let destination = directory.appendingPathComponent("complete.m4a")
        async let playback = cache.read(at: 3, through: 7)
        async let offline: Void = cache.fill(destination: destination) { _ in }
        let firstBytes = try await playback
        try await offline
        XCTAssertEqual(firstBytes, source[3..<7])
        XCTAssertEqual(try Data(contentsOf: destination), source)
        let fetched = await requests.ranges
        XCTAssertEqual(Set(fetched), Set([0..<8, 8..<16, 16..<24, 24..<25]))
        XCTAssertEqual(fetched.count, 4)
    }

    func testAACSeekAndRetryKeepVerifiedBlocksAcrossAnInterruption() async throws {
        let source = Data((0..<32).map(UInt8.init))
        let recorder = AACInterruptionFixture(source: source)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try AACRangeCache(length: 32, directory: directory, blockSize: 8,
                                      retryDelays: [.milliseconds(5), .milliseconds(5)]) { range in
            try await recorder.fetch(range)
        }
        let seek = try await cache.read(at: 26, through: 29)
        XCTAssertEqual(seek, source[26..<29])
        let requestsBeforeDownload = await recorder.ranges
        XCTAssertEqual(requestsBeforeDownload, [24..<32, 24..<32, 24..<32])

        let destination = directory.appendingPathComponent("complete.m4a")
        try await cache.fill(destination: destination) { _ in }
        XCTAssertEqual(try Data(contentsOf: destination), source)
        let requests = await recorder.ranges
        XCTAssertEqual(requests.filter { $0 == 24..<32 }.count, 3)
    }

    func testCancellingAACDownloadReleasesItsNetworkWorkAndCanRetry() async throws {
        let source = Data((0..<32).map(UInt8.init))
        let blocked = expectation(description: "Requested uncached block")
        blocked.assertForOverFulfill = false
        let recorder = AACInterruptionFixture(source: source, blocked: blocked)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = try AACRangeCache(length: 32, directory: directory, blockSize: 8) { range in
            try await recorder.fetch(range)
        }
        _ = try await cache.read(at: 0, through: 8)

        let destination = directory.appendingPathComponent("complete.m4a")
        let cancelled = expectation(description: "Download cancelled while the CDN was blocked")
        let running = Task {
            do {
                try await cache.fill(destination: destination) { _ in }
                XCTFail("A cancelled download was published")
            } catch is CancellationError {
                cancelled.fulfill()
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
        await fulfillment(of: [blocked], timeout: 2)
        running.cancel()
        await fulfillment(of: [cancelled], timeout: 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))

        await recorder.unblock()
        try await cache.fill(destination: destination) { _ in }
        XCTAssertEqual(try Data(contentsOf: destination), source)
        let requests = await recorder.ranges
        XCTAssertEqual(requests.filter { $0 == 0..<8 }.count, 1)
    }

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

private actor AACRequestRecorder {
    let source: Data
    private(set) var ranges: [Range<Int64>] = []

    init(source: Data) {
        self.source = source
    }

    func fetch(_ range: Range<Int64>) async throws -> Data {
        ranges.append(range)
        try await Task.sleep(nanoseconds: 20_000_000)
        return source.subdata(in: Int(range.lowerBound)..<Int(range.upperBound))
    }
}

private actor AACInterruptionFixture {
    let source: Data
    var blocked: XCTestExpectation?
    private(set) var ranges: [Range<Int64>] = []

    init(source: Data, blocked: XCTestExpectation? = nil) {
        self.source = source
        self.blocked = blocked
    }

    func unblock() { blocked = nil }

    func fetch(_ range: Range<Int64>) async throws -> Data {
        ranges.append(range)
        if range.lowerBound > 0, let blocked {
            blocked.fulfill()
            try await Task.sleep(for: .seconds(3))
        }
        if range == 24..<32, ranges.filter({ $0 == range }).count < 3, blocked == nil {
            throw URLError(.networkConnectionLost)
        }
        return source.subdata(in: Int(range.lowerBound)..<Int(range.upperBound))
    }
}
