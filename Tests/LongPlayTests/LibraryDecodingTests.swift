import XCTest
@testable import LongPlay

final class LibraryDecodingTests: XCTestCase {
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
