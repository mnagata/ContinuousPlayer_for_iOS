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
        app.launchArguments = ["--ui-dlna-direct-only"]
        app.launch()
        defer { app.terminate() }

        openAddDLNA(app)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.firstMatch.waitForExistence(timeout: 2) {
            let allow = springboard.alerts.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "許可", "OK"])).firstMatch
            if allow.exists { allow.tap() }
        }
        let forget = app.buttons["保存した接続先を削除"]
        if forget.exists {
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: forget)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
            forget.tap()
        }
        let address = app.textFields["dlna.serverAddress"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.tap()
        address.typeText("http://127.0.0.1:18765/folders.xml")
        app.buttons["dlna.connect"].tap()
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
        if register.label.contains("登録解除") {
            register.tap()
            let ready = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label CONTAINS %@", "このフォルダーを登録"), object: register)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 5), .completed)
        }
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
        XCTAssertTrue(app.buttons["作品 OP.mp4から連続再生"].waitForExistence(timeout: 15))

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
        app.launchArguments = ["--ui-dlna-direct-only"]
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
        let file = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        let listing = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        listing.name = "dlna-folder"
        listing.lifetime = .keepAlways
        add(listing)
        file.tap()
        XCTAssertTrue(app.staticTexts["最後まで再生しました"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["作品 ED.mp4"].firstMatch.exists)
        let playback = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        playback.name = "dlna-playback"
        playback.lifetime = .keepAlways
        add(playback)
        app.buttons["OP / EDを選び直す"].tap()
        XCTAssertTrue(file.waitForExistence(timeout: 5), "Return to the same DLNA folder")
        file.tap()
        XCTAssertTrue(app.staticTexts["最後まで再生しました"].waitForExistence(timeout: 20))
        app.buttons["ホームに戻る"].tap()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 5))
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
