import XCTest

final class Stage1PlaybackUITests: XCTestCase {
    func testSelectionCancelAndInformation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state", "--ui-dlna-direct-only",
                               "-dlna.lastServerAddress", "127.0.0.1:18767"]
        app.launch()
        defer { app.terminate() }
        app.buttons["home.select"].tap()
        app.buttons["saved.addFolder"].tap()
        app.buttons["saved.source.dlna"].tap()
        let server = app.buttons["Fixture NAS"]
        XCTAssertTrue(server.waitForExistence(timeout: 20))
        server.tap()
        let register = app.buttons["dlna.registerFolder"]
        XCTAssertTrue(register.waitForExistence(timeout: 15))
        if register.label.contains("登録解除") { register.tap() }
        register.tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.' AND label CONTAINS 'Fixture NAS'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.tap()
        let op = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(op.waitForExistence(timeout: 15))
        op.tap()
        assertState(app, contains: "作品 OP.mp4|playing|")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        assertState(app, contains: "作品 OP.mp4|paused|")
        app.buttons["メディア情報"].tap()
        XCTAssertTrue(app.navigationBars["メディア情報"].waitForExistence(timeout: 5))
        app.buttons["閉じる"].tap()
        assertState(app, contains: "作品 OP.mp4|paused|")
        app.buttons["OP / EDを選び直す"].tap()
        XCTAssertTrue(op.waitForExistence(timeout: 10))
        app.buttons["dlna.cancel"].tap()
        assertState(app, contains: "作品 OP.mp4|paused|")
        app.buttons["OP / EDを選び直す"].tap()
        XCTAssertTrue(op.waitForExistence(timeout: 10))
        op.tap()
        assertState(app, contains: "作品 OP.mp4|playing|")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        assertState(app, contains: "作品 OP.mp4|paused|")
        app.buttons["OP / EDを選び直す"].tap()
        let ed = app.buttons["作品 ED.mp4から連続再生"]
        XCTAssertTrue(ed.waitForExistence(timeout: 10))
        ed.tap()
        assertState(app, contains: "作品 ED.mp4|playing|")
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        assertState(app, contains: "作品 ED.mp4|paused|")
        app.buttons["再生"].firstMatch.tap()
        assertState(app, contains: "作品 ED.mp4|playing|")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        assertState(app, contains: "作品 ED.mp4|paused|")
        app.buttons["ホームに戻る"].tap()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 5))
    }

    private func assertState(_ app: XCUIApplication, contains text: String) {
        let state = app.staticTexts["player.sessionState"]
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text), object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, text)
    }
}
