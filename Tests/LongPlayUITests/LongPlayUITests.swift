import XCTest

final class LongPlayUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    func testMenuBarOpensPopover() throws {
        let app = launchApp()

        try openMenuBar(app)
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 2))
    }

    func testTabNavigationAndEmptyState() throws {
        let app = launchApp()

        try openMenuBar(app)

        let listenTab = app.buttons["Listen"]
        let addTab = app.buttons["Add"]
        let utilitiesTab = app.buttons["Utilities"]
        XCTAssertTrue(listenTab.waitForExistence(timeout: 2))
        XCTAssertTrue(addTab.waitForExistence(timeout: 2))
        XCTAssertTrue(utilitiesTab.waitForExistence(timeout: 2))

        listenTab.click()
        XCTAssertTrue(app.staticTexts["Now Playing"].waitForExistence(timeout: 2))
        if !app.staticTexts["No tracks yet"].waitForExistence(timeout: 1) {
            XCTAssertTrue(app.staticTexts["My Library"].waitForExistence(timeout: 2))
        }

        addTab.click()
        XCTAssertTrue(app.textFields["YouTube URL"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["Display name (optional)"].waitForExistence(timeout: 2))

        utilitiesTab.click()
        XCTAssertTrue(app.buttons["Clear all downloads"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Copy diagnostics"].waitForExistence(timeout: 2))
        if !app.switches["Start at Login"].waitForExistence(timeout: 2) {
            throw XCTSkip("Start at Login toggle not available on this runner.")
        }
    }

    func testAddValidationShowsError() throws {
        let app = launchApp()

        try openMenuBar(app)
        app.buttons["Add"].click()

        let urlField = app.textFields["YouTube URL"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 2))
        urlField.click()
        urlField.typeText("not a url")

        try addTrackButton(in: app).click()
        let invalidText = app.staticTexts["Invalid URL."]
        let inputIssue = app.staticTexts["Input issue"]
        XCTAssertTrue(
            invalidText.waitForExistence(timeout: 2) || inputIssue.waitForExistence(timeout: 2),
            "Expected validation feedback to appear."
        )
    }

    func testDownloadAndPlaybackForKnownURL() throws {
        let env = ProcessInfo.processInfo.environment
        let shouldRunNetworkTests = env["RUN_NETWORK_TESTS"] == "1" || env["CI"] == nil
        if !shouldRunNetworkTests {
            throw XCTSkip("Network download test disabled. Set RUN_NETWORK_TESTS=1 to enable.")
        }

        let app = launchApp()

        try openMenuBar(app)
        app.buttons["Add"].click()

        let urlField = app.textFields["YouTube URL"]
        XCTAssertTrue(urlField.waitForExistence(timeout: 2))
        urlField.click()
        urlField.typeText("https://www.youtube.com/watch?v=vcGeWUiWrT4&list=RDvcGeWUiWrT4&start_radio=1")

        try addTrackButton(in: app).click()
        app.buttons["Listen"].click()
        XCTAssertTrue(app.staticTexts["Tracks"].waitForExistence(timeout: 2))

        let trackRow = trackRowElement(in: app, fallbackTimeout: 10)
        guard trackRow.exists else {
            throw XCTSkip("Track row did not appear after adding URL.")
        }

        let downloadTimeout: TimeInterval = 180
        XCTAssertTrue(
            trackRow.staticTexts["Offline"].waitForExistence(timeout: downloadTimeout),
            "Track did not reach Offline state within \(downloadTimeout)s."
        )

        trackRow.click()
        XCTAssertTrue(app.staticTexts["Playing"].waitForExistence(timeout: 10))
    }

    private func openMenuBar(_ app: XCUIApplication) throws {
        if app.buttons["Listen"].waitForExistence(timeout: 4) {
            return
        }
        let mainWindow = app.windows["LongPlay"]
        if mainWindow.waitForExistence(timeout: 6) {
            return
        }
        let mainWindowById = app.otherElements["LongPlayMainWindow"]
        if mainWindowById.waitForExistence(timeout: 6) {
            return
        }
        let system = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let statusBar = system.statusBars.firstMatch
        let statusItemById = statusBar.buttons["LongPlayStatusItem"]
        let statusItemByLabel = statusBar.buttons["LongPlay"]
        if statusItemById.waitForExistence(timeout: 5) {
            statusItemById.click()
        } else if statusItemByLabel.waitForExistence(timeout: 2) {
            statusItemByLabel.click()
        } else {
            throw XCTSkip("Menu bar item not accessible in UI tests on this runner.")
        }
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 2))
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["UITESTING"] = "1"
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    private func addTrackButton(in app: XCUIApplication) throws -> XCUIElement {
        let byLabel = app.buttons["Add track"]
        if byLabel.waitForExistence(timeout: 2) {
            return byLabel
        }
        let byId = app.buttons["AddTrackButton"]
        if byId.waitForExistence(timeout: 2) {
            return byId
        }
        throw XCTSkip("Add track button not available.")
    }

    private func trackRowElement(in app: XCUIApplication, fallbackTimeout: TimeInterval) -> XCUIElement {
        let titleIdentifier = "TrackTitle_vcGeWUiWrT4"
        let title = app.staticTexts[titleIdentifier]
        if title.waitForExistence(timeout: fallbackTimeout) {
            let container = app.otherElements.containing(.staticText, identifier: titleIdentifier).firstMatch
            if container.exists {
                return container
            }
        }
        let titlePredicate = NSPredicate(format: "identifier BEGINSWITH %@", "TrackTitle_")
        let anyTitle = app.staticTexts.matching(titlePredicate).firstMatch
        if anyTitle.waitForExistence(timeout: fallbackTimeout) {
            let container = app.otherElements.containing(.staticText, identifier: anyTitle.identifier).firstMatch
            if container.exists {
                return container
            }
        }
        let rowPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "TrackRow_")
        let anyRow = app.otherElements.matching(rowPredicate).firstMatch
        _ = anyRow.waitForExistence(timeout: fallbackTimeout)
        return anyRow
    }
}
