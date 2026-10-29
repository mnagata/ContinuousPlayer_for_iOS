import XCTest

final class Stage1TVPlaybackUITests: XCTestCase {
    func testBackOnceCancelResumeAndSelection() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state",
                               "-dlna.lastServerAddress", "127.0.0.1:18765"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["home.chooseFolder"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.select)
        activate(app.buttons["saved.addFolder"])
        activate(app.buttons["saved.source.dlna"])
        activate(app.buttons["Fixture NAS"])
        let register = app.buttons["dlna.registerFolder"]
        XCTAssertTrue(register.waitForExistence(timeout: 15))
        if register.label.contains("登録解除") { activate(register) }
        activate(register)
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).firstMatch
        activate(saved)
        let op = app.buttons["作品 OP.mp4から連続再生"]
        activate(op)
        assertState(app, "作品 OP.mp4|playing|")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(op.waitForExistence(timeout: 10), "One Back opens the file list")
        activate(app.buttons["dlna.cancel"])
        assertState(app, "作品 OP.mp4|playing|")
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(op.waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        reopenFromTVHome(app)
        activate(app.buttons["dlna.cancel"])
        assertState(app, "作品 OP.mp4|paused|")
        XCUIRemote.shared.press(.playPause)
        assertState(app, "作品 OP.mp4|playing|")
        XCUIRemote.shared.press(.playPause)
        assertState(app, "作品 OP.mp4|paused|")
        XCUIRemote.shared.press(.menu)
        activate(app.buttons["dlna.cancel"])
        assertState(app, "作品 OP.mp4|paused|")
        XCUIRemote.shared.press(.menu)
        activate(op)
        assertState(app, "作品 OP.mp4|playing|")
        XCUIRemote.shared.press(.menu)
        activate(app.buttons["作品 ED.mp4から連続再生"])
        assertState(app, "作品 ED.mp4|playing|")
        XCUIRemote.shared.press(.playPause)
        assertState(app, "作品 ED.mp4|paused|")
        activate(app.buttons["メディア情報"])
        XCTAssertTrue(app.buttons["player.info.close"].waitForExistence(timeout: 10))
        XCUIRemote.shared.press(.menu)
        assertState(app, "作品 ED.mp4|paused|")
        activate(app.buttons["ホームに戻る"])
        XCTAssertTrue(app.buttons["home.chooseFolder"].waitForExistence(timeout: 10))
    }

    private func assertState(_ app: XCUIApplication, _ text: String) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", text),
                                                   object: app.staticTexts["player.sessionState"])
        let result = XCTWaiter.wait(for: [expectation], timeout: 15)
        if result != .completed { print(app.debugDescription) }
        XCTAssertEqual(result, .completed, text)
    }

    private func activate(_ element: XCUIElement) {
        let exists = element.waitForExistence(timeout: 20)
        if !exists { print(XCUIApplication().debugDescription) }
        XCTAssertTrue(exists)
        if !isFocused(element) {
            for _ in 0..<30 {
                let current = (XCUIApplication().buttons.allElementsBoundByIndex + XCUIApplication().textFields.allElementsBoundByIndex).first(where: isFocused)
                if let current {
                    let dx = element.frame.midX - current.frame.midX
                    let dy = element.frame.midY - current.frame.midY
                    if abs(dy) > max(10, current.frame.height / 2) {
                        XCUIRemote.shared.press(dy < 0 ? .up : .down)
                    } else {
                        XCUIRemote.shared.press(dx < 0 ? .left : .right)
                    }
                } else {
                    XCUIRemote.shared.press(.down)
                }
                if isFocused(element) { break }
            }
        }
        XCTAssertTrue(isFocused(element), "Focus: \(element.label)")
        XCUIRemote.shared.press(.select)
    }

    private func isFocused(_ element: XCUIElement) -> Bool {
        if element.hasFocus { return true }
        let cell = XCUIApplication().cells.containing(.button, identifier: element.label).firstMatch
        return cell.exists && cell.hasFocus
    }

    private func reopenFromTVHome(_ app: XCUIApplication) {
        let home = XCUIApplication(bundleIdentifier: "com.apple.PineBoard")
        let icon = home.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "ContinuousPlayer")).firstMatch
        guard icon.waitForExistence(timeout: 3) else {
            // tvOS 27's launcher currently omits icons from its AX tree and
            // activate() may leave UIKit in background. Permit a real remote
            // selection in Device Hub, and verify UIKit activity, not just PID.
            print("TV_HOME_MANUAL_REOPEN: select ContinuousPlayer in Device Hub")
            let foreground = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@", "|app=0"),
                                                       object: app.staticTexts["player.sessionState"])
            XCTAssertEqual(XCTWaiter.wait(for: [foreground], timeout: 120), .completed)
            return
        }
        for _ in 0..<8 {
            if icon.hasFocus { break }
            XCUIRemote.shared.press(.right)
        }
        XCTAssertTrue(icon.hasFocus, "Select the app icon with the remote")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
