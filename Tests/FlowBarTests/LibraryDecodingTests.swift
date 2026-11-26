import XCTest
@testable import FlowBar

final class LibraryDecodingTests: XCTestCase {
    func testLegacyVideoIDUsesTheAlreadyResolvedTitle() throws {
        var track = makeTrack()
        XCTAssertEqual(track.title, "YouTube track")
        track.resolvedTitle = "Title from YouTube"

        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertEqual(decoded.title, "Title from YouTube")
    }

    func testRenameSurvivesMetadataAndReloadEvenWhenNameEqualsVideoID() throws {
        var track = makeTrack()
        XCTAssertTrue(track.rename(to: "  \(track.videoId)\n"))
        track.resolvedTitle = "Title from YouTube"

        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(Track.self, from: data)
        XCTAssertEqual(decoded.title, track.videoId)
        XCTAssertFalse(track.rename(to: " \n"))
        XCTAssertEqual(track.title, track.videoId)
    }

    func testExistingCustomNameWinsOverResolvedTitle() {
        var track = makeTrack()
        track.displayName = "My mix"
        track.resolvedTitle = "Title from YouTube"
        XCTAssertEqual(track.title, "My mix")
    }

    private func makeTrack() -> Track {
        Track.makeNew(
            sourceURL: URL(string: "https://www.youtube.com/watch?v=JRnDYB28bL8")!,
            videoId: "JRnDYB28bL8",
            displayName: "JRnDYB28bL8"
        )
    }

    func testDecodingDefaultsCacheLimitWhenMissing() throws {
        let json = """
        {
          "schemaVersion": 1,
          "userLibrary": []
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let library = try decoder.decode(Library.self, from: data)

        XCTAssertEqual(library.schemaVersion, 1)
        XCTAssertEqual(library.cacheLimitBytes, Library.defaultCacheLimitBytes)
    }

    func testDecodingKeepsCacheLimitWhenPresent() throws {
        let json = """
        {
          "schemaVersion": 2,
          "userLibrary": [],
          "cacheLimitBytes": 1234
        }
        """
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoder = JSONDecoder()
        let library = try decoder.decode(Library.self, from: data)

        XCTAssertEqual(library.schemaVersion, 2)
        XCTAssertEqual(library.cacheLimitBytes, 1234)
    }
}
