import XCTest

final class Stage4InputUITests: XCTestCase {
    private func launchListing(nested: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state",
            "--ui-dlna-direct-only", "-dlna.lastServerAddress",
            "http://127.0.0.1:18767/" + (nested ? "folders.xml" : "description.xml")]
        app.launch()
        app.buttons["home.select"].tap()
        app.buttons["saved.addFolder"].tap()
        app.buttons["saved.source.dlna"].tap()
        let server = app.buttons["Fixture NAS"]
        XCTAssertTrue(server.waitForExistence(timeout: 15)); server.tap()
        if nested {
            let folder = app.buttons["dlna.folder.folder-0"]
            XCTAssertTrue(folder.waitForExistence(timeout: 15)); folder.tap()
        }
        app.buttons["dlna.registerFolder"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
        return app
    }
    private func startPlayer() -> XCUIApplication {
        let app = launchListing()
        let op = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(op.waitForExistence(timeout: 15)); op.tap()
        state(app, name: "作品 OP.mp4", playing: true)
        return app
    }
    private func state(_ app: XCUIApplication, name: String, playing: Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS 'presenting=false'",
            "\(name)|\(playing ? "playing" : "paused")|"), object: app.staticTexts["player.sessionState"])
        let result = XCTWaiter.wait(for: [expectation], timeout: 15)
        if result != .completed { print(app.staticTexts["player.sessionState"].label); print(app.staticTexts["player.inputState"].label); print(app.buttons["player.video"].value ?? "nil") }
        XCTAssertEqual(result, .completed)
    }
    private func seconds(_ app: XCUIApplication) -> Double {
        Double(app.staticTexts["player.sessionState"].label.split(separator: "|")[2]) ?? -1
    }
    private func position(_ app: XCUIApplication, near target: Double) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in abs(self.seconds(app) - target) < 0.7 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 10), .completed)
    }
    func testDirectTouchDoubleTapSwipeAndLongHold() {
        let app = startPlayer(); defer { app.terminate() }
        let video = app.buttons["player.video"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        video.tap()
        state(app, name: "作品 OP.mp4", playing: false)
        let before = seconds(app)
        video.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).doubleTap()
        position(app, near: before + 10)
        video.doubleTap()
        state(app, name: "作品 OP.mp4", playing: true)
        video.swipeLeft()
        state(app, name: "作品 ED.mp4", playing: true)
        video.swipeRight()
        state(app, name: "作品 OP.mp4", playing: true)
        video.press(forDuration: 1)
        state(app, name: "作品 OP.mp4", playing: true)
        video.pinch(withScale: 1.4, velocity: 1)
        state(app, name: "作品 OP.mp4", playing: true)
        video.tap()
        state(app, name: "作品 OP.mp4", playing: false)
        app.buttons["OP / EDを選び直す"].tap()
        let ed = app.buttons["作品 ED.mp4から連続再生"]
        XCTAssertTrue(ed.waitForExistence(timeout: 10)); ed.press(forDuration: 1)
        XCTAssertTrue(ed.exists, "File long press must not play or show information")
        XCTAssertFalse(app.navigationBars["メディア情報"].exists)
        app.buttons["dlna.cancel"].tap()
        state(app, name: "作品 OP.mp4", playing: false)
    }
    func testKeyboardPlaybackModalPriorityAndHome() {
        let app = startPlayer(); defer { app.terminate() }
        app.typeKey(.space, modifierFlags: [])
        state(app, name: "作品 OP.mp4", playing: false)
        app.typeKey(.rightArrow, modifierFlags: [])
        state(app, name: "作品 ED.mp4", playing: false)
        app.typeKey(.space, modifierFlags: [])
        state(app, name: "作品 ED.mp4", playing: true)
        app.typeKey(.space, modifierFlags: [])
        state(app, name: "作品 ED.mp4", playing: false)
        app.typeKey(.leftArrow, modifierFlags: [])
        state(app, name: "作品 OP.mp4", playing: false)
        app.typeKey(.downArrow, modifierFlags: [])
        position(app, near: 10)
        app.typeKey(.rightArrow, modifierFlags: .shift)
        position(app, near: 20)
        app.typeKey("i", modifierFlags: [])
        XCTAssertTrue(app.navigationBars["メディア情報"].waitForExistence(timeout: 5))
        app.typeKey(.rightArrow, modifierFlags: [])
        XCTAssertTrue(app.navigationBars["メディア情報"].exists)
        app.typeKey("i", modifierFlags: [])
        state(app, name: "作品 OP.mp4", playing: false)
        app.typeKey("o", modifierFlags: [])
        XCTAssertTrue(app.buttons["作品 OP.mp4から連続再生"].waitForExistence(timeout: 10))
        app.typeKey("h", modifierFlags: [])
        XCTAssertTrue(app.buttons["作品 OP.mp4から連続再生"].exists)
        app.buttons["dlna.cancel"].tap()
        state(app, name: "作品 OP.mp4", playing: false)
        app.typeKey("h", modifierFlags: [])
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 5))
    }
    func testInformationShortcutClosesWhilePlayingAndAfterNavigation() {
        let app = startPlayer(); defer { app.terminate() }
        for cycle in 0..<3 {
            let modifiers: XCUIElement.KeyModifierFlags = cycle == 2 ? .shift : []
            app.typeKey("i", modifierFlags: modifiers)
            let close = app.buttons["player.info.close"]
            XCTAssertTrue(close.waitForExistence(timeout: 5))
            if cycle == 1 { app.typeKey(.tab, modifierFlags: []) }
            app.typeKey(.rightArrow, modifierFlags: [])
            XCTAssertTrue(close.exists)
            app.typeKey("i", modifierFlags: modifiers)
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !close.exists }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            state(app, name: "作品 OP.mp4", playing: true)
        }
    }
    func testListPagesAndAddressTyping() {
        let app = launchListing(nested: true); defer { app.terminate() }
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dlna.folder.child-' AND selected == true"))
        XCTAssertTrue(selected.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(selected.firstMatch.identifier, "dlna.folder.child-0")
        app.typeKey(.rightArrow, modifierFlags: [])
        let paged = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let id = selected.firstMatch.identifier
            return id != "dlna.folder.child-0" && id != "dlna.folder.child-1"
        }, object: nil)
        let result = XCTWaiter.wait(for: [paged], timeout: 10)
        print(app.staticTexts["selection.inputState"].label)
        XCTAssertEqual(result, .completed)
        let forwardID = selected.firstMatch.identifier
        let forwardIndex = Int(forwardID.components(separatedBy: "child-").last!)!
        app.typeKey(.leftArrow, modifierFlags: [])
        let earlier = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let index = Int(selected.firstMatch.identifier.components(separatedBy: "child-").last ?? "") ?? forwardIndex
            return index <= forwardIndex - 2
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [earlier], timeout: 5), .completed)
        // Visible row count can differ after scrolling. Page repeatedly to the
        // boundary, then verify an additional Up cannot wrap to the last row.
        for _ in 0..<3 { app.typeKey(.leftArrow, modifierFlags: []) }
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertEqual(selected.firstMatch.identifier, "dlna.folder.child-0")
        app.buttons["dlna.cancel"].tap()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 5))
        app.buttons["home.select"].tap()
        app.buttons["saved.addFolder"].tap()
        app.buttons["saved.source.dlna"].tap()
        let clear = app.buttons["dlna.clearAddress"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10)); clear.tap()
        let address = app.textFields["dlna.serverAddress"]
        address.tap(); address.typeText("ioh")
        XCTAssertEqual(address.value as? String, "ioh")
        app.typeKey(.leftArrow, modifierFlags: [])
        app.typeKey("i", modifierFlags: [])
        XCTAssertTrue(app.navigationBars["DLNAサーバー"].exists)
        // The hardware key can enter marked Japanese text under the user's IME.
        XCTAssertTrue(["ioih", "ioいh"].contains(address.value as? String ?? ""))
    }
}
