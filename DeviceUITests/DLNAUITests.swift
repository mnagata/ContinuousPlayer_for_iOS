import XCTest

/// Run with scripts/test-dlna-ui.sh, which provides the loopback server.
final class DLNAUITests: XCTestCase {
    private func openAddDLNA(_ app: XCUIApplication) {
        let select = app.buttons["home.select"]
        XCTAssertTrue(select.waitForExistence(timeout: 10))
        select.tap()
        let add = app.buttons["saved.addFolder"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        let source = app.buttons["saved.source.dlna"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        XCTAssertTrue(app.navigationBars["DLNAサーバー"].waitForExistence(timeout: 10))
    }

    func testRegisterNestedFolderFromAddDialog() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This test uses the Mac's loopback fixture server; run on Simulator.")
        #endif
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-dlna-direct-only",
                               "-dlna.lastServerAddress", "http://127.0.0.1:18765/folders.xml"]
        app.launch()
        defer { app.terminate() }

        openAddDLNA(app)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可", "OK"])).firstMatch
            if allow.exists { allow.tap() }
        }
        // This case tests folder registration. Seed the server independently of
        // keyboard timing and the previous run's saved connection.
        let server = app.buttons["Fixture NAS"]
        XCTAssertTrue(server.waitForExistence(timeout: 15))
        server.tap()
        let folder = app.buttons["dlna.folder.folder-0"]
        XCTAssertTrue(folder.waitForExistence(timeout: 15))
        folder.tap()
        let child = app.buttons["dlna.folder.child-0"]
        XCTAssertTrue(child.waitForExistence(timeout: 15))
        child.tap()
        let register = app.buttons["dlna.registerFolder"]
        XCTAssertTrue(register.waitForExistence(timeout: 15))
        XCTAssertTrue(register.isEnabled)
        register.tap()
        XCTAssertTrue(app.navigationBars["保存済みフォルダー"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Child 00"].waitForExistence(timeout: 10))
        let saved = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH 'saved.dlna.' AND label CONTAINS %@", "Child 00")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.tap()
        XCTAssertTrue(app.navigationBars["Child 00"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.navigationBars["DLNAサーバー"].exists)
        XCTAssertFalse(app.buttons["dlna.registerFolder"].exists)
        let file = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(file.waitForExistence(timeout: 15))

        file.tap()
        XCTAssertTrue(app.staticTexts["このフォルダーの再生が終了しました。"].waitForExistence(timeout: 20))
        app.buttons["ファイル一覧"].tap()
        XCTAssertTrue(file.waitForExistence(timeout: 10), "Open the currently playing folder")
        XCTAssertEqual(app.buttons["selection.back"].label, "保存済みフォルダー")
        app.buttons["selection.back"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "Registration root returns to saved folders")
        XCTAssertFalse(folder.exists, "Do not expose ancestors above the registered root")
        saved.tap()
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        app.buttons["dlna.cancel"].tap()
        XCTAssertTrue(app.buttons["ホームに戻る"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["作品 ED.mp4"].firstMatch.exists, "Cancel keeps the paused video")

        app.launchArguments.removeAll { $0 == "--ui-reset-registrations" }
        app.terminate()
        app.launch()
        app.buttons["home.select"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()
        XCTAssertTrue(app.navigationBars["Child 00"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.navigationBars["DLNAサーバー"].exists)
        XCTAssertFalse(app.buttons["dlna.registerFolder"].exists)
        XCTAssertTrue(app.buttons["作品 OP.mp4から連続再生"].waitForExistence(timeout: 15))
    }

    func testBrowsePlayAndReturnToFolder() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This test uses the Mac's loopback fixture server; run on Simulator.")
        #endif
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-dlna-direct-only",
                               "-dlna.lastServerAddress", ""]
        app.launch()
        defer { app.terminate() }
        openAddDLNA(app)
        // Accept the system prompt if the simulator shows it.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可", "OK"])).firstMatch
            if allow.exists { allow.tap() }
        }
        XCTAssertFalse(app.buttons["dlna.refreshServers"].exists, "Do not offer unavailable multicast discovery")
        let forget = app.buttons["保存した接続先を削除"]
        if forget.exists {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: forget)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
            forget.tap()
        }
        XCTAssertTrue(app.staticTexts["dlna.directConnectionNotice"].exists)
        let url = app.textFields["dlna.serverAddress"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { url.tap() }
        url.typeText("http://127.0.0.1:18765/management")
        app.buttons["dlna.connect"].tap()
        let issue = app.staticTexts["dlna.connectionErrorTitle"]
        XCTAssertTrue(issue.waitForExistence(timeout: 10))
        XCTAssertEqual(issue.label, "DLNAサーバーの応答ではありません")
        XCTAssertTrue(app.staticTexts["dlna.connectionErrorGuidance"].label.contains("別のサービス"))
        app.buttons["接続エラーの詳細"].tap()
        XCTAssertTrue(app.staticTexts["dlna.connectionErrorDetails"].label.contains("/management"))
        let failure = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        failure.name = "dlna-connection-guidance"
        failure.lifetime = .keepAlways
        add(failure)
        app.buttons["dlna.clearAddress"].tap()
        url.tap()
        // A host and port are enough; no XML path and no multicast permission.
        url.typeText("127.0.0.1:18765")
        app.buttons["dlna.connect"].tap()
        let server = app.buttons["Fixture NAS"]
        XCTAssertTrue(server.waitForExistence(timeout: 15))
        server.tap()
        let register = app.buttons["dlna.registerFolder"]
        XCTAssertTrue(register.waitForExistence(timeout: 15))
        register.tap()
        let saved = app.buttons["saved.dlna.uuid:fixture\u{0}0"]
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
        let file = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        let listing = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        listing.name = "dlna-folder"
        listing.lifetime = .keepAlways
        add(listing)
        file.tap()
        XCTAssertTrue(app.staticTexts["このフォルダーの再生が終了しました。"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["作品 ED.mp4"].firstMatch.exists)
        let playback = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        playback.name = "dlna-playback"
        playback.lifetime = .keepAlways
        add(playback)
        app.buttons["ファイル一覧"].tap()
        XCTAssertTrue(file.waitForExistence(timeout: 5), "Return to the same DLNA folder")
        file.tap()
        XCTAssertTrue(app.staticTexts["このフォルダーの再生が終了しました。"].waitForExistence(timeout: 20))
        app.buttons["ホームに戻る"].tap()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 5))
        app.launchArguments.removeAll { $0 == "--ui-reset-registrations" }
        app.launchArguments.removeLast(2) // Let the saved address drive reconnection after relaunch.
        app.terminate()
        app.launch()
        openAddDLNA(app)
        XCTAssertTrue(server.waitForExistence(timeout: 15), "Restore and reconnect to the saved NAS without multicast")
        XCTAssertEqual(url.value as? String, "127.0.0.1:18765")
        XCTAssertFalse(app.buttons["dlna.refreshServers"].exists)
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: forget)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        forget.tap()
        XCTAssertFalse(server.exists)
        XCTAssertTrue(app.staticTexts["dlna.directConnectionNotice"].exists)
    }
}
