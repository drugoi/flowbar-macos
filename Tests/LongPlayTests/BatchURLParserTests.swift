import XCTest
@testable import LongPlay

final class BatchURLParserTests: XCTestCase {
    func testSplitsOnWhitespaceAndNewlines() {
        let input = "https://example.com/one\nhttps://example.com/two https://example.com/three\thttps://example.com/four"
        let result = BatchURLParser.parse(input)
        XCTAssertEqual(result, [
            "https://example.com/one",
            "https://example.com/two",
            "https://example.com/three",
            "https://example.com/four"
        ])
    }

    func testPreservesCommasInsideURLs() {
        let first = "https://youtube.com/watch?v=VIDEO_ID&list=PLAYLIST,ID"
        let second = "https://youtube.com/watch?v=VIDEO_ID_2"
        let result = BatchURLParser.parse("\(first) \(second)")
        XCTAssertEqual(result, [first, second])
    }

    func testTrimsAndSkipsEmptyEntries() {
        let result = BatchURLParser.parse("  https://example.com/one  \n\n \t  https://example.com/two  ")
        XCTAssertEqual(result, [
            "https://example.com/one",
            "https://example.com/two"
        ])
    }

    func testEmptyInputReturnsEmptyArray() {
        let result = BatchURLParser.parse("   \n\t ")
        XCTAssertTrue(result.isEmpty)
    }
}
