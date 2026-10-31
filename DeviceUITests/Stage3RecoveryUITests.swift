import XCTest

/// Uses the loopback server started by scripts/test-playback-recovery-ui.sh.
final class Stage3RecoveryUITests: XCTestCase {
    private let base = "http://127.0.0.1:18768"
    private func launch(folder: String = "failure") throws -> XCUIApplication {
        continueAfterFailure = false
        _ = try Data(contentsOf: URL(string: base + "/test/reset-missing")!)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state",
                               "--ui-dlna-direct-only", "-dlna.lastServerAddress", base + "/description.xml"]
        app.launch()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 10))
        app.buttons["home.select"].tap()
        app.buttons["saved.addFolder"].tap()
        app.buttons["saved.source.dlna"].tap()
        let server = app.buttons["Common Spec Fixture"]
        XCTAssertTrue(server.waitForExistence(timeout: 15)); server.tap()
        let target = app.buttons["dlna.folder." + folder]
        XCTAssertTrue(target.waitForExistence(timeout: 15)); target.tap()
        app.buttons["dlna.registerFolder"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
        return app
    }
    private func state(_ app: XCUIApplication, name: String, playing: Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@",
            "\(name)|\(playing ? "playing" : "paused")|"), object: app.staticTexts["player.sessionState"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
    }
    private func select(_ app: XCUIApplication, _ name: String) {
        let file = app.buttons[name + "から連続再生"]
        XCTAssertTrue(file.waitForExistence(timeout: 15)); file.tap()
    }
    func testErrorCloseBrowseRetryAndInformation() throws {
        let app = try launch(); defer { app.terminate() }
        select(app, "Missing OP.mp4")
        let retry = app.buttons["player.error.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["player.error.next"].exists)
        XCTAssertTrue(app.buttons["player.error.browse"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'NASとネットワーク'")).firstMatch.exists)
        app.buttons["player.error.close"].tap()
        state(app, name: "Missing OP.mp4", playing: false)
        XCTAssertFalse(retry.exists)
        XCTAssertFalse(app.buttons["10秒進める"].firstMatch.isEnabled)
        app.buttons["ファイル一覧"].tap()
        select(app, "Missing OP.mp4")
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        app.buttons["player.error.browse"].tap()
        XCTAssertTrue(app.buttons["Missing OP.mp4から連続再生"].waitForExistence(timeout: 10))
        app.buttons["dlna.cancel"].tap()
        state(app, name: "Missing OP.mp4", playing: false)
        app.buttons["ファイル一覧"].tap()
        select(app, "Missing OP.mp4")
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        _ = try Data(contentsOf: URL(string: base + "/test/restore-missing")!)
        state(app, name: "Missing OP.mp4", playing: false)
        retry.tap()
        state(app, name: "Missing OP.mp4", playing: true)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        state(app, name: "Missing OP.mp4", playing: false)
        app.buttons["メディア情報"].tap()
        XCTAssertTrue(app.navigationBars["メディア情報"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["ファイル"].exists)
        XCTAssertTrue(app.staticTexts["映像・音声形式"].exists)
        XCTAssertTrue(app.staticTexts["音声出力"].exists)
        app.buttons["player.info.close"].tap()
        state(app, name: "Missing OP.mp4", playing: false)
        app.buttons["ファイル一覧"].tap()
        select(app, "Unavailable OP.mp4")
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["player.error.next"].exists, "Last item offers no next action")
        app.buttons["player.error.close"].tap()
        app.buttons["ホームに戻る"].tap()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 5))
    }
    func testExplicitErrorNextStartsPlayableFile() throws {
        let app = try launch(); defer { app.terminate() }
        select(app, "Missing OP.mp4")
        let next = app.buttons["player.error.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 20)); next.tap()
        state(app, name: "Playable ED.mp4", playing: true)
        XCTAssertFalse(app.buttons["player.error.retry"].exists)
    }
    func testPreparationTimeoutStaysSelected() throws {
        let app = try launch(folder: "slow-media"); defer { app.terminate() }
        select(app, "Slow OP.mp4")
        XCTAssertTrue(app.buttons["player.error.retry"].waitForExistence(timeout: 45))
        state(app, name: "Slow OP.mp4", playing: false)
        XCTAssertTrue(app.staticTexts["再試行位置: 0.0秒"].exists)
        XCTAssertFalse(app.buttons["player.error.next"].exists)
        app.buttons["player.error.close"].tap()
        state(app, name: "Slow OP.mp4", playing: false)
    }
}
