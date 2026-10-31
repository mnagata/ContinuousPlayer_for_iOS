import XCTest

final class Stage4TVInputUITests: XCTestCase {
    private func launchListing(nested: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state",
            "-dlna.lastServerAddress", "http://127.0.0.1:18765/" + (nested ? "folders.xml" : "description.xml")]
        app.launch()
        activate(app.buttons["home.chooseFolder"])
        activate(app.buttons["saved.addFolder"])
        activate(app.buttons["saved.source.dlna"])
        activate(app.buttons["Fixture NAS"])
        if nested { activate(app.buttons["dlna.folder.folder-0"]) }
        activate(app.buttons["dlna.registerFolder"])
        activate(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).firstMatch)
        return app
    }
    private func state(_ app: XCUIApplication, _ name: String, playing: Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS 'presenting=false'",
            "\(name)|\(playing ? "playing" : "paused")|"), object: app.staticTexts["player.sessionState"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
    }
    private func seconds(_ app: XCUIApplication) -> Double {
        Double(app.staticTexts["player.sessionState"].label.split(separator: "|")[2]) ?? -1
    }
    func testVideoDirectionsSelectHoldAndButtonPriority() {
        let app = launchListing(); defer { app.terminate() }
        activate(app.buttons["作品 OP.mp4から連続再生"])
        state(app, "作品 OP.mp4", playing: true)
        XCUIRemote.shared.press(.right)
        state(app, "作品 ED.mp4", playing: true)
        XCUIRemote.shared.press(.left)
        state(app, "作品 OP.mp4", playing: true)
        XCUIRemote.shared.press(.down)
        let seek = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.seconds(app) > 9 && self.seconds(app) < 14 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [seek], timeout: 10), .completed)
        XCUIRemote.shared.press(.up)
        let back = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.seconds(app) < 5 }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [back], timeout: 10), .completed)
        XCUIRemote.shared.press(.select, forDuration: 1)
        state(app, "作品 OP.mp4", playing: false)
        let toggle = app.buttons["player.toggle"]
        let focus = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.isFocused(toggle) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [focus], timeout: 5), .completed)
        XCUIRemote.shared.press(.right)
        state(app, "作品 OP.mp4", playing: false)
        XCTAssertTrue(isFocused(app.buttons["10秒進める"]), "Arrows on a button navigate the controls")
        XCUIRemote.shared.press(.select)
        state(app, "作品 OP.mp4", playing: false)
        activate(toggle)
        state(app, "作品 OP.mp4", playing: true)
        let video = app.otherElements["player.video"]
        let videoFocus = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.isFocused(video) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [videoFocus], timeout: 5), .completed)
        XCUIRemote.shared.press(.playPause)
        state(app, "作品 OP.mp4", playing: false)
        XCUIRemote.shared.press(.playPause)
        state(app, "作品 OP.mp4", playing: true)
        XCUIRemote.shared.press(.menu)
        let file = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        focusElement(file)
        XCUIRemote.shared.press(.select, forDuration: 1)
        XCTAssertTrue(file.exists, "File long select is not play or info")
        XCTAssertFalse(app.staticTexts["映像・音声形式"].exists)
        activate(app.buttons["dlna.cancel"])
        state(app, "作品 OP.mp4", playing: true)
    }
    func testListPagesUseVisibleRowsAndDoNotWrap() {
        let app = launchListing(nested: true); defer { app.terminate() }
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'dlna.folder.child-' AND selected == true"))
        XCTAssertTrue(selected.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(selected.firstMatch.identifier, "dlna.folder.child-0")
        XCUIRemote.shared.press(.right)
        let page = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let id = selected.firstMatch.identifier
            return id != "dlna.folder.child-0" && id != "dlna.folder.child-1"
        }, object: nil)
        let result = XCTWaiter.wait(for: [page], timeout: 10)
        print(app.staticTexts["selection.inputState"].label)
        XCTAssertEqual(result, .completed)
        for _ in 0..<3 { XCUIRemote.shared.press(.left) }
        let first = app.buttons["dlna.folder.child-0"]
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.isFocused(first) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [restored], timeout: 5), .completed)
        XCUIRemote.shared.press(.up)
        XCTAssertTrue(isFocused(first))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["saved.addFolder"].waitForExistence(timeout: 5))
    }
    private func isFocused(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        if element.hasFocus || element.descendants(matching: .button).allElementsBoundByIndex.contains(where: { $0.hasFocus }) { return true }
        let cell = XCUIApplication().cells.containing(.button, identifier: element.label).firstMatch
        return cell.exists && cell.hasFocus
    }
    private func activate(_ element: XCUIElement) { focusElement(element); XCUIRemote.shared.press(.select) }
    private func focusElement(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 20))
        for _ in 0..<45 {
            if isFocused(element) { return }
            let app = XCUIApplication()
            let current = (app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex + app.textFields.allElementsBoundByIndex).first { $0.hasFocus }
            if let current {
                let dx = element.frame.midX - current.frame.midX, dy = element.frame.midY - current.frame.midY
                if abs(dy) > max(10, current.frame.height / 2) { XCUIRemote.shared.press(dy < 0 ? .up : .down) }
                else { XCUIRemote.shared.press(dx < 0 ? .left : .right) }
            } else { XCUIRemote.shared.press(.down) }
        }
        print(XCUIApplication().debugDescription)
        XCTFail("Could not focus \(element.label)")
    }
}
