import XCTest

/// Run with scripts/test-dlna-ui.sh, which provides the loopback server.
final class DLNAUITests: XCTestCase {
    func testBrowsePlayAndReturnToFolder() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("This test uses the Mac's loopback fixture server; run on Simulator.")
        #endif
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-dlna-direct-only"]
        app.launch()
        defer { app.terminate() }
        let dlna = app.buttons["home.selectDLNA"]
        XCTAssertTrue(dlna.waitForExistence(timeout: 10))
        if !dlna.isHittable { app.swipeUp() }
        dlna.tap()
        XCTAssertTrue(app.navigationBars["DLNAサーバー"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(dlna.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(dlna.waitForExistence(timeout: 10))
        if !dlna.isHittable { app.swipeUp() }
        dlna.tap()
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
