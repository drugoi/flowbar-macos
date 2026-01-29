import XCTest
@testable import FlowBar

final class URLValidatorTests: XCTestCase {
    func testValidWatchURL() {
        let result = URLValidator.validate("https://www.youtube.com/watch?v=SetrYp0FEtw")
        switch result {
        case .success(let validated):
            XCTAssertEqual(validated.videoId, "SetrYp0FEtw")
            XCTAssertEqual(validated.canonicalURL.absoluteString, "https://www.youtube.com/watch?v=SetrYp0FEtw")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testValidWatchURLWithPlaylistParameters() {
        let url = "https://www.youtube.com/watch?v=QZE18q0LcKw&list=RDQZE18q0LcKw&start_radio=1"
        let result = URLValidator.validate(url)
        switch result {
        case .success(let validated):
            XCTAssertEqual(validated.videoId, "QZE18q0LcKw")
            XCTAssertEqual(validated.canonicalURL.absoluteString, "https://www.youtube.com/watch?v=QZE18q0LcKw")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testValidShortURL() {
        let result = URLValidator.validate("https://youtu.be/ObT0RaT_woU")
        switch result {
        case .success(let validated):
            XCTAssertEqual(validated.videoId, "ObT0RaT_woU")
            XCTAssertEqual(validated.canonicalURL.absoluteString, "https://www.youtube.com/watch?v=ObT0RaT_woU")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testValidShortsURL() {
        let result = URLValidator.validate("https://www.youtube.com/shorts/SetrYp0FEtw")
        switch result {
        case .success(let validated):
            XCTAssertEqual(validated.videoId, "SetrYp0FEtw")
            XCTAssertEqual(validated.canonicalURL.absoluteString, "https://www.youtube.com/watch?v=SetrYp0FEtw")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testRejectsUnsupportedScheme() {
        let result = URLValidator.validate("ftp://www.youtube.com/watch?v=SetrYp0FEtw")
        switch result {
        case .success:
            XCTFail("Expected failure for unsupported scheme")
        case .failure(let error):
            XCTAssertEqual(error, .unsupportedScheme)
        }
    }

    func testRejectsUnsupportedHost() {
        let result = URLValidator.validate("https://example.com/watch?v=SetrYp0FEtw")
        switch result {
        case .success:
            XCTFail("Expected failure for unsupported host")
        case .failure(let error):
            XCTAssertEqual(error, .unsupportedHost)
        }
    }

    func testRejectsMissingVideoId() {
        let result = URLValidator.validate("https://www.youtube.com/watch?v=")
        switch result {
        case .success:
            XCTFail("Expected failure for missing video id")
        case .failure(let error):
            XCTAssertEqual(error, .missingVideoId)
        }
    }

    func testTrimsWhitespace() {
        let result = URLValidator.validate("  https://www.youtube.com/watch?v=SetrYp0FEtw  ")
        switch result {
        case .success(let validated):
            XCTAssertEqual(validated.videoId, "SetrYp0FEtw")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }
}
