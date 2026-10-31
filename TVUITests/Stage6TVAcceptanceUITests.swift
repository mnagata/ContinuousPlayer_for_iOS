import XCTest

final class Stage6TVAcceptanceUITests: XCTestCase {
    func testThirtySecondCancelAndProcessRestart() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state",
            "-dlna.lastServerAddress", "http://127.0.0.1:18765/description.xml"]
        app.launch(); defer { app.terminate() }
        activate(app.buttons["home.chooseFolder"])
        activate(app.buttons["saved.addFolder"])
        activate(app.buttons["saved.source.dlna"])
        activate(app.buttons["Fixture NAS"])
        activate(app.buttons["dlna.registerFolder"])
        activate(saved(app))
        activate(app.buttons["作品 OP.mp4から連続再生"])
        state(app, playing: true)
        XCUIRemote.shared.press(.playPause)
        state(app, playing: false)
        for _ in 0..<3 {
            let target = seconds(app) + 10
            activate(app.buttons["10秒進める"])
            position(app, near: target, tolerance: 0.7)
        }
        XCTAssertEqual(seconds(app), 30, accuracy: 4)
        let paused = seconds(app)
        XCUIRemote.shared.press(.menu)
        activate(app.buttons["dlna.cancel"])
        state(app, playing: false)
        position(app, near: paused, tolerance: 0.7)
        XCUIRemote.shared.press(.playPause)
        state(app, playing: true)
        let before = seconds(app)
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(app.buttons["作品 OP.mp4から連続再生"].waitForExistence(timeout: 10))
        activate(app.buttons["dlna.cancel"])
        state(app, playing: true)
        position(app, near: before, tolerance: 4)
        print("STAGE6 TV playing cancel: before=\(before), after=\(seconds(app))")
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-reset-registrations" }
        app.launch()
        XCTAssertTrue(app.buttons["home.chooseFolder"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["player.video"].exists)
        activate(app.buttons["home.chooseFolder"])
        XCTAssertTrue(saved(app).waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["player.video"].exists)
        activate(saved(app))
        activate(app.buttons["作品 OP.mp4から連続再生"])
        state(app, playing: true)
        XCTAssertLessThan(seconds(app), 4)
    }

    private func saved(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).firstMatch
    }
    private func state(_ app: XCUIApplication, playing: Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS 'presenting=false'",
            "作品 OP.mp4|\(playing ? "playing" : "paused")|"), object: app.staticTexts["player.sessionState"])
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed)
    }
    private func seconds(_ app: XCUIApplication) -> Double {
        let fields = app.staticTexts["player.sessionState"].label.split(separator: "|")
        return fields.count > 2 ? Double(fields[2]) ?? -1 : -1
    }
    private func position(_ app: XCUIApplication, near target: Double, tolerance: Double) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            abs(self.seconds(app) - target) <= tolerance
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed, "target=\(target), actual=\(seconds(app))")
    }
    private func activate(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 20))
        for _ in 0..<45 {
            if focused(element) { XCUIRemote.shared.press(.select); return }
            let app = XCUIApplication()
            let current = (app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex + app.textFields.allElementsBoundByIndex).first { $0.hasFocus }
            if let current {
                let dx = element.frame.midX - current.frame.midX, dy = element.frame.midY - current.frame.midY
                if abs(dy) > max(10, current.frame.height / 2) { XCUIRemote.shared.press(dy < 0 ? .up : .down) }
                else { XCUIRemote.shared.press(dx < 0 ? .left : .right) }
            } else { XCUIRemote.shared.press(.down) }
        }
        XCTFail("Could not focus \(element.label): \(XCUIApplication().debugDescription)")
    }
    private func focused(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        if element.hasFocus { return true }
        let cell = XCUIApplication().cells.containing(.button, identifier: element.label).firstMatch
        return cell.exists && cell.hasFocus
    }
}
