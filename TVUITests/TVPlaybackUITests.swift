import XCTest

/// Uses the same loopback DLNA fixture as the iOS integration tests.
final class TVPlaybackUITests: XCTestCase {
    func testRemoteBrowsePlaybackAndReturn() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-dlna.lastServerAddress", "127.0.0.1:18765"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["home.dlna"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.select)
        let server = app.buttons["Fixture NAS"]
        XCTAssertTrue(server.waitForExistence(timeout: 20))
        let settingsShot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        settingsShot.name = "tvOS-IP-settings"
        settingsShot.lifetime = .keepAlways
        add(settingsShot)
        XCTAssertFalse(app.buttons["dlna.refreshServers"].exists)
        try focus(server)
        XCUIRemote.shared.press(.select)
        let file = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        try focus(file)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.staticTexts["このフォルダーの再生が終了しました。"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["作品 ED.mp4"].exists, "Advance from OP to ED automatically")
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "tvOS-playback-ended"
        shot.lifetime = .keepAlways
        add(shot)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(file.waitForExistence(timeout: 10), "Return to the same folder using Back")
        try focus(file)
        XCUIRemote.shared.press(.select)
        let video = app.otherElements["player.video"]
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        XCTAssertEqual(video.value as? String, "作品 OP.mp4")
        XCUIRemote.shared.press(.right)
        XCTAssertEqual(video.value as? String, "作品 OP.mp4", "Right press must not skip to ED")
        XCUIRemote.shared.press(.left)
        XCTAssertEqual(video.value as? String, "作品 OP.mp4", "Left press must not change the file")
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.buttons["player.toggle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["player.toggle"].label, "再生")
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.staticTexts["このフォルダーの再生が終了しました。"].waitForExistence(timeout: 30))
    }

    func testBackRestoresNestedFolderPositionAndFocus() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-dlna.lastServerAddress", "http://127.0.0.1:18765/folders.xml"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["home.dlna"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.select)
        let server = app.buttons["Fixture NAS"]
        XCTAssertTrue(server.waitForExistence(timeout: 20))
        try focus(server)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Folder 00"].waitForExistence(timeout: 10))
        let folder = app.buttons["Folder 25"]
        try focus(folder)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["Child 00"].waitForExistence(timeout: 10))
        let child = app.buttons["Child 20"]
        try focus(child)
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.buttons["作品 OP.mp4から連続再生"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.menu)
        assertRestored(child)
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "tvOS-restored-folder"
        shot.lifetime = .keepAlways
        add(shot)
        // The next remote press must continue from the restored row, not from the top.
        XCUIRemote.shared.press(.down)
        assertRestored(app.buttons["Child 21"])
        XCUIRemote.shared.press(.menu)
        assertRestored(folder)
        XCUIRemote.shared.press(.select)
        assertRestored(child)
    }

    private func assertRestored(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.isFocused(element) && element.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed,
                       "The previous folder must be visible and focused without directional input", file: file, line: line)
    }

    private func isFocused(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        if element.hasFocus { return true }
        let cell = XCUIApplication().cells.containing(.button, identifier: element.label).firstMatch
        return cell.exists && cell.hasFocus
    }

    private func focus(_ element: XCUIElement) throws {
        if isFocused(element) { return }
        for _ in 0..<60 {
            XCUIRemote.shared.press(.down)
            if isFocused(element) { return }
        }
        print(XCUIApplication().debugDescription)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTFail("Could not focus \(element.label) with the remote")
    }
}
