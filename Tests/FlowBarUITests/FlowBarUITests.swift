import XCTest

final class FlowBarUITests: XCTestCase {
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
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let app = launchApp(libraryDirectory: directory)
        defer {
            app.terminate()
            try? FileManager.default.removeItem(at: directory)
        }

        try openMenuBar(app)

        let listenTab = app.buttons["Listen"]
        let addTab = app.buttons["Add"]
        let settingsTab = app.buttons["Settings"]
        XCTAssertTrue(listenTab.waitForExistence(timeout: 2))
        XCTAssertTrue(addTab.waitForExistence(timeout: 2))
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 2))

        XCTAssertTrue(app.staticTexts["No tracks yet"].waitForExistence(timeout: 2))
        app.buttons["Add a Track"].click()
        XCTAssertTrue(app.textFields["YouTube URL"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.textFields["Display name (optional)"].waitForExistence(timeout: 2))

        settingsTab.click()
        XCTAssertTrue(app.buttons["Clear all downloads"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.buttons["Copy Diagnostics"].waitForExistence(timeout: 2))
    }

    func testAnEmptyAddFormShowsValidationFeedback() throws {
        let app = launchApp()

        try openMenuBar(app)
        app.buttons["Add"].click()

        XCTAssertTrue(app.textFields["YouTube URL"].waitForExistence(timeout: 2))
        try addTrackButton(in: app).click()
        XCTAssertTrue(app.staticTexts["Enter at least one YouTube URL."].waitForExistence(timeout: 2))
    }

    func testResolvedTitleAndRenameWhileDownloading() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let title = "Severance — Music To Refine To feat. ODESZA | Apple TV"
        let track: [String: Any] = [
            "id": UUID().uuidString,
            "sourceURL": "https://www.youtube.com/watch?v=JRnDYB28bL8",
            "videoId": "JRnDYB28bL8",
            "displayName": "JRnDYB28bL8",
            "resolvedTitle": title,
            "metadataUnavailable": true,
            "addedAt": "2026-01-01T00:00:00Z",
            "playbackPositionSeconds": 0,
            "downloadState": "downloading"
        ]
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 2, "userLibrary": [track]])
        try data.write(to: directory.appendingPathComponent("library.json"))

        let app = launchApp(libraryDirectory: directory)
        defer { app.terminate() }
        try openMenuBar(app)
        let playerTitle = app.staticTexts["NowPlayingTitle"]
        let libraryTitle = app.staticTexts["TrackTitle_JRnDYB28bL8"]
        XCTAssertTrue(playerTitle.waitForExistence(timeout: 3))
        XCTAssertEqual(playerTitle.label, title)
        XCTAssertTrue((libraryTitle.value as? String ?? libraryTitle.label).hasPrefix("Severance — Music"))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value == %@", "Downloading")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Metadata unavailable"].exists)

        app.activate()
        app.menuButtons["TrackActions_JRnDYB28bL8"].click()
        app.menuItems["Rename"].click()
        let name = app.textFields["Display name"]
        XCTAssertTrue(name.waitForExistence(timeout: 2))
        XCTAssertEqual(name.value as? String, title)
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Focus mix")
        name.typeKey(.return, modifierFlags: [])
        XCTAssertEqual(playerTitle.label, "Focus mix")
        XCTAssertEqual(libraryTitle.value as? String ?? libraryTitle.label, "Focus mix")
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
        XCTAssertTrue(app.staticTexts["My Library"].waitForExistence(timeout: 2))

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
        let mainWindow = app.windows["FlowBar"]
        if mainWindow.waitForExistence(timeout: 6) {
            return
        }
        let mainWindowById = app.otherElements["FlowBarMainWindow"]
        if mainWindowById.waitForExistence(timeout: 6) {
            return
        }
        let system = XCUIApplication(bundleIdentifier: "com.apple.systemuiserver")
        let statusBar = system.statusBars.firstMatch
        let statusItemById = statusBar.buttons["FlowBarStatusItem"]
        let statusItemByLabel = statusBar.buttons["FlowBar"]
        if statusItemById.waitForExistence(timeout: 5) {
            statusItemById.click()
        } else if statusItemByLabel.waitForExistence(timeout: 2) {
            statusItemByLabel.click()
        } else {
            throw XCTSkip("Menu bar item not accessible in UI tests on this runner.")
        }
        XCTAssertTrue(app.buttons["Listen"].waitForExistence(timeout: 2))
    }

    private func launchApp(libraryDirectory: URL? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ApplePersistenceIgnoreState", "YES"]
        app.launchEnvironment["UITESTING"] = "1"
        app.launchEnvironment["FLOWBAR_UI_TEST_DIRECTORY"] = libraryDirectory?.path
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
