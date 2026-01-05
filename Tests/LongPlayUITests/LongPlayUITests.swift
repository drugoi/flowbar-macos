import XCTest

final class LongPlayUITests: XCTestCase {
    func testMenuBarOpensPopover() throws {
        let app = XCUIApplication()
        app.launch()

        let system = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let statusItem = system.statusBars.firstMatch.buttons["LongPlay"]
        if statusItem.waitForExistence(timeout: 5) {
            statusItem.click()
        } else {
            throw XCTSkip("Menu bar item not accessible in UI tests on this runner.")
        }

        XCTAssertTrue(app.buttons["AddTrackButton"].waitForExistence(timeout: 2))
    }
}
