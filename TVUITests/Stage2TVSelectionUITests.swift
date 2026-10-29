import XCTest

final class Stage2TVSelectionUITests: XCTestCase {
    func testRegisteredRootRemovalAdditionCancelAndHome() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state",
                               "-dlna.lastServerAddress", "http://127.0.0.1:18765/folders.xml"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["home.chooseFolder"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.select)
        activate(app.buttons["saved.addFolder"])
        XCTAssertFalse(app.buttons["saved.source.local"].exists)
        activate(app.buttons["saved.source.dlna"])
        activate(app.buttons["Fixture NAS"])
        activate(app.buttons["dlna.folder.folder-0"])
        activate(app.buttons["dlna.folder.child-0"])
        activate(app.buttons["dlna.registerFolder"])
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.' AND label CONTAINS 'Child 00'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.isFocused(saved) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 10), .completed)
        activate(saved)
        let op = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(op.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["dlna.folder.folder-0"].exists)
        activate(op)
        state(app, playing: true)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(op.waitForExistence(timeout: 15))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(saved.waitForExistence(timeout: 10), "Root Back opens saved list, never ancestors")
        focus(saved)
        XCUIRemote.shared.press(.select, forDuration: 1)
        XCTAssertTrue(app.alerts["登録を解除しますか？"].waitForExistence(timeout: 5), "Long select opens confirmation directly")
        activate(app.alerts.buttons["登録解除"].firstMatch)
        let removed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: saved)
        XCTAssertEqual(XCTWaiter.wait(for: [removed], timeout: 5), .completed)
        let add = app.buttons["saved.addFolder"]
        let addedFocus = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.isFocused(add) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [addedFocus], timeout: 10), .completed)
        activate(add)
        activate(app.buttons["saved.source.dlna"])
        activate(app.buttons["Fixture NAS"])
        activate(app.buttons["dlna.folder.folder-0"])
        activate(app.buttons["dlna.folder.child-1"])
        activate(app.buttons["dlna.registerFolder"])
        activate(app.buttons["saved.close"])
        state(app, playing: true)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(op.waitForExistence(timeout: 15), "Active source remains available after unregister")
        activate(app.buttons["selection.home"])
        XCTAssertTrue(app.buttons["home.chooseFolder"].waitForExistence(timeout: 10), "Home closes every selection page")
    }
    private func state(_ app: XCUIApplication, playing: Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS 'presenting=false'",
            "作品 OP.mp4|\(playing ? "playing" : "paused")|"), object: app.staticTexts["player.sessionState"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
    }
    private func isFocused(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        if element.hasFocus || element.descendants(matching: .button).allElementsBoundByIndex.contains(where: { $0.hasFocus }) { return true }
        let cell = XCUIApplication().cells.containing(.button, identifier: element.label).firstMatch
        return cell.exists && cell.hasFocus
    }
    private func activate(_ element: XCUIElement) { focus(element); XCUIRemote.shared.press(.select) }
    private func focus(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 20))
        for _ in 0..<45 {
            if isFocused(element) { return }
            let current = (XCUIApplication().buttons.allElementsBoundByIndex + XCUIApplication().cells.allElementsBoundByIndex + XCUIApplication().textFields.allElementsBoundByIndex).first(where: { $0.hasFocus })
            if let current {
                let dx = element.frame.midX - current.frame.midX
                let dy = element.frame.midY - current.frame.midY
                if abs(dy) > max(10, current.frame.height / 2) { XCUIRemote.shared.press(dy < 0 ? .up : .down) }
                else { XCUIRemote.shared.press(dx < 0 ? .left : .right) }
            } else { XCUIRemote.shared.press(.down) }
        }
        print(XCUIApplication().debugDescription)
        XCTFail("Could not focus \(element.label)")
    }
}
