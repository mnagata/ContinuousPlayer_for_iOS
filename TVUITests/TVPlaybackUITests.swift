import XCTest

/// Uses the same loopback DLNA fixture as the iOS integration tests.
final class TVPlaybackUITests: XCTestCase {
    func testRemoteBrowsePlaybackAndReturn() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "-dlna.lastServerAddress", "127.0.0.1:18765"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["home.chooseFolder"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.select)
        let addFolder = app.buttons["saved.addFolder"]
        XCTAssertTrue(addFolder.waitForExistence(timeout: 10))
        try focus(addFolder)
        XCUIRemote.shared.press(.select)
        let source = app.buttons["saved.source.dlna"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        try focus(source)
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
        let registerFolder = app.buttons["dlna.registerFolder"]
        XCTAssertTrue(registerFolder.waitForExistence(timeout: 10))
        try focus(registerFolder)
        XCUIRemote.shared.press(.select)
        let savedFolder = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "saved.dlna.")).firstMatch
        XCTAssertTrue(savedFolder.waitForExistence(timeout: 10), "Registration returns to saved folders")
        try focus(savedFolder)
        XCUIRemote.shared.press(.select)
        let file = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(file.waitForExistence(timeout: 20), "Saved folder opens without choosing the server again")
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
        let next = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "作品 ED.mp4"), object: video)
        XCTAssertEqual(XCTWaiter.wait(for: [next], timeout: 10), .completed, "Right direction selects the next file")
        XCUIRemote.shared.press(.left)
        let previous = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "作品 OP.mp4"), object: video)
        XCTAssertEqual(XCTWaiter.wait(for: [previous], timeout: 10), .completed, "Left direction selects the previous file")
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.buttons["player.toggle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["player.toggle"].label, "再生")
        XCUIRemote.shared.press(.playPause)
        XCTAssertTrue(app.staticTexts["このフォルダーの再生が終了しました。"].waitForExistence(timeout: 30))
    }

    func testBackRestoresNestedFolderPositionAndFocus() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "-dlna.lastServerAddress", "http://127.0.0.1:18765/folders.xml"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["home.chooseFolder"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.select)
        let addFolder = app.buttons["saved.addFolder"]
        XCTAssertTrue(addFolder.waitForExistence(timeout: 10))
        try focus(addFolder)
        XCUIRemote.shared.press(.select)
        let source = app.buttons["saved.source.dlna"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        try focus(source)
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
            let app = XCUIApplication()
            let focused = (app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex).first { $0.hasFocus }
            if let focused {
                let dx = element.frame.midX - focused.frame.midX, dy = element.frame.midY - focused.frame.midY
                if abs(dy) > max(10, focused.frame.height / 2) { XCUIRemote.shared.press(dy < 0 ? .up : .down) }
                else { XCUIRemote.shared.press(dx < 0 ? .left : .right) }
            } else { XCUIRemote.shared.press(.down) }
            if isFocused(element) { return }
        }
        print(XCUIApplication().debugDescription)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTFail("Could not focus \(element.label) with the remote")
    }
}
