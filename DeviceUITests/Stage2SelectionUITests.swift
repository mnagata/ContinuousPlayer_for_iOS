import XCTest

final class Stage2SelectionUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state", "--ui-dlna-direct-only",
                               "-dlna.lastServerAddress", "http://127.0.0.1:18767/folders.xml"]
        app.launch()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 10))
        app.buttons["home.select"].tap()
        return app
    }
    private func add(_ app: XCUIApplication, nested: Bool) {
        app.buttons["saved.addFolder"].tap()
        app.buttons["saved.source.dlna"].tap()
        let server = app.buttons["Fixture NAS"]
        XCTAssertTrue(server.waitForExistence(timeout: 15))
        server.tap()
        if nested {
            let folder = app.buttons["dlna.folder.folder-0"]
            XCTAssertTrue(folder.waitForExistence(timeout: 15)); folder.tap()
            let child = app.buttons["dlna.folder.child-0"]
            XCTAssertTrue(child.waitForExistence(timeout: 15)); child.tap()
        }
        let register = app.buttons["dlna.registerFolder"]
        XCTAssertTrue(register.waitForExistence(timeout: 15)); register.tap()
        XCTAssertTrue(app.navigationBars["保存済みフォルダー"].waitForExistence(timeout: 10))
    }
    private func state(_ app: XCUIApplication, _ name: String, playing: Bool, presenting: Bool = false) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@",
            "\(name)|\(playing ? "playing" : "paused")|", "presenting=\(presenting)"), object: app.staticTexts["player.sessionState"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
    }
    func testNestedRootUpsertRemovalAndCancelPreservePlayer() {
        let app = launch(); defer { app.terminate() }
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).count, 0)
        add(app, nested: true)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.' AND label CONTAINS 'Child 00'")).firstMatch
        XCTAssertTrue(saved.exists)
        let id = saved.identifier
        add(app, nested: true)
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).count, 1)
        XCTAssertEqual(saved.identifier, id)
        saved.tap()
        let op = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(op.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["selection.back"].label, "保存済みフォルダー")
        XCTAssertFalse(app.buttons["dlna.registerFolder"].exists)
        op.tap(); state(app, "作品 OP.mp4", playing: true)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        state(app, "作品 OP.mp4", playing: false)
        app.buttons["ファイル一覧"].tap()
        XCTAssertTrue(op.waitForExistence(timeout: 15))
        XCTAssertEqual(app.buttons["selection.back"].label, "保存済みフォルダー")
        app.buttons["selection.back"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        saved.press(forDuration: 1)
        XCTAssertTrue(app.alerts["登録を解除しますか？"].waitForExistence(timeout: 5))
        app.alerts.buttons["登録解除"].tap()
        XCTAssertFalse(saved.exists)
        add(app, nested: false)
        app.buttons["saved.close"].tap()
        state(app, "作品 OP.mp4", playing: false)
        app.buttons["ファイル一覧"].tap()
        XCTAssertTrue(op.waitForExistence(timeout: 10), "Removed current registration remains usable for the active session")
        app.buttons["dlna.cancel"].tap()
        state(app, "作品 OP.mp4", playing: false)
        app.buttons["ホームに戻る"].tap()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 5))
    }
    func testBackFromPlaybackRevealsDepartedDirectoryInLongList() {
        let app = launch(); defer { app.terminate() }
        add(app, nested: false)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).firstMatch
        saved.tap()
        let folder = app.buttons["dlna.folder.folder-0"]
        XCTAssertTrue(folder.waitForExistence(timeout: 15)); folder.tap()
        let child = app.buttons["dlna.folder.child-24"]
        let list = app.collectionViews["picker.customList"]
        for _ in 0..<12 {
            if child.isHittable { break }
            list.swipeUp()
        }
        XCTAssertTrue(child.isHittable); child.tap()
        let op = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(op.waitForExistence(timeout: 15)); op.tap()
        state(app, "作品 OP.mp4", playing: true)
        app.buttons["player.video"].tap()
        state(app, "作品 OP.mp4", playing: false)
        app.buttons["ファイル一覧"].tap()
        XCTAssertTrue(op.waitForExistence(timeout: 15))
        app.buttons["selection.back"].tap()
        let revealed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            child.isSelected && child.isHittable
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [revealed], timeout: 10), .completed,
                       "Back selects and scrolls to the departed directory in an unvisited parent")
        app.buttons["selection.back"].tap()
        XCTAssertTrue(folder.waitForExistence(timeout: 15))
        XCTAssertTrue(folder.isSelected && folder.isHittable)
        app.buttons["selection.back"].tap()
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertTrue(saved.isSelected && saved.isHittable)
    }
    func testSlowReloadRetainsRowsAndBackCancelsWholeFlow() throws {
        let app = launch(); defer { app.terminate() }
        add(app, nested: true)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).firstMatch.tap()
        let op = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(op.waitForExistence(timeout: 15)); op.tap()
        state(app, "作品 OP.mp4", playing: true)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()
        state(app, "作品 OP.mp4", playing: false)
        app.buttons["ファイル一覧"].tap()
        XCTAssertTrue(op.waitForExistence(timeout: 15))
        _ = try Data(contentsOf: URL(string: "http://127.0.0.1:18767/test/delay-next?seconds=6")!)
        app.buttons["selection.reload"].tap()
        XCTAssertTrue(op.exists)
        XCTAssertFalse(op.isEnabled)
        XCTAssertTrue(app.buttons["dlna.cancel"].isEnabled)
        XCTAssertTrue(app.otherElements["selection.loading"].waitForExistence(timeout: 3) || app.activityIndicators["selection.loading"].exists)
        app.buttons["selection.back"].tap()
        state(app, "作品 OP.mp4", playing: false)
        let resurrected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.buttons["selection.reload"])
        resurrected.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [resurrected], timeout: 7), .completed)
    }
    func testSystemPickerCancelReturnsToSourceAndAddCancelToSaved() {
        let app = launch(); defer { app.terminate() }
        app.buttons["saved.addFolder"].tap()
        app.buttons["saved.source.local"].tap()
        // The document service's close icon is not reliably present in XCTest's
        // AX tree on these runtimes. Allow a native UI driver to close it, then
        // verify the destination rather than treating the assisted step as automated.
        print("NATIVE_PICKER_CANCEL_ASSIST: close native picker in Device Hub")
        let sourceReady = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: app.buttons["saved.source.dlna"])
        XCTAssertEqual(XCTWaiter.wait(for: [sourceReady], timeout: 120), .completed)
        app.buttons["saved.source.close"].tap()
        XCTAssertTrue(app.buttons["saved.addFolder"].waitForExistence(timeout: 5))
        app.buttons["saved.addFolder"].tap()
        app.buttons["selection.back"].tap()
        XCTAssertTrue(app.buttons["saved.addFolder"].waitForExistence(timeout: 5))
    }
}
