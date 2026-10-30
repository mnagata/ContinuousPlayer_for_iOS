import XCTest

final class Stage3TVRecoveryUITests: XCTestCase {
    private let base = "http://127.0.0.1:18769"
    private func launch(folder: String = "failure") throws -> XCUIApplication {
        continueAfterFailure = false
        _ = try Data(contentsOf: URL(string: base + "/test/reset-missing")!)
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state",
                               "-dlna.lastServerAddress", base + "/description.xml"]
        app.launch()
        activate(app.buttons["home.chooseFolder"])
        activate(app.buttons["saved.addFolder"])
        activate(app.buttons["saved.source.dlna"])
        activate(app.buttons["Common Spec Fixture"])
        activate(app.buttons["dlna.folder." + folder])
        activate(app.buttons["dlna.registerFolder"])
        activate(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).firstMatch)
        return app
    }
    private func state(_ app: XCUIApplication, _ name: String, playing: Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS 'presenting=false'",
            "\(name)|\(playing ? "playing" : "paused")|"), object: app.staticTexts["player.sessionState"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed)
    }
    private func choose(_ app: XCUIApplication, _ name: String) { activate(app.buttons[name + "から連続再生"]) }
    func testErrorFocusRetryBrowseCloseNextAndOutputInformation() throws {
        let app = try launch(); defer { app.terminate() }
        choose(app, "Missing OP.mp4")
        let retry = app.buttons["player.error.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        let preferred = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.isFocused(retry) }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [preferred], timeout: 10), .completed, "Error initially focuses retry")
        _ = try Data(contentsOf: URL(string: base + "/test/restore-missing")!)
        XCUIRemote.shared.press(.select)
        state(app, "Missing OP.mp4", playing: true)
        XCUIRemote.shared.press(.playPause)
        state(app, "Missing OP.mp4", playing: false)
        activate(app.buttons["メディア情報"])
        XCTAssertTrue(app.staticTexts["ファイル"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["映像・音声形式"].exists)
        XCTAssertTrue(app.staticTexts["音声出力"].exists)
        XCTAssertTrue(app.staticTexts["実際の出力設定"].exists)
        XCUIRemote.shared.press(.menu)
        state(app, "Missing OP.mp4", playing: false)
        XCTAssertFalse(app.buttons["dlna.cancel"].exists, "Info Back closes only info")
        _ = try Data(contentsOf: URL(string: base + "/test/reset-missing")!)
        activate(app.buttons["player.chooseFolder"])
        choose(app, "Missing OP.mp4")
        activate(app.buttons["player.error.browse"])
        XCTAssertTrue(app.buttons["Missing OP.mp4から連続再生"].waitForExistence(timeout: 10))
        activate(app.buttons["dlna.cancel"])
        state(app, "Missing OP.mp4", playing: false)
        activate(app.buttons["player.chooseFolder"])
        choose(app, "Missing OP.mp4")
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        XCUIRemote.shared.press(.menu)
        state(app, "Missing OP.mp4", playing: false)
        XCTAssertFalse(retry.exists)
        XCTAssertFalse(app.buttons["dlna.cancel"].exists, "Error Back must not also open file list")
        XCTAssertFalse(app.buttons["10秒進める"].firstMatch.isEnabled)
        activate(app.buttons["player.chooseFolder"])
        choose(app, "Missing OP.mp4")
        activate(app.buttons["player.error.next"])
        state(app, "Playable ED.mp4", playing: true)
        XCUIRemote.shared.press(.playPause)
        activate(app.buttons["player.chooseFolder"])
        choose(app, "Unavailable OP.mp4")
        XCTAssertTrue(retry.waitForExistence(timeout: 20))
        XCTAssertFalse(app.buttons["player.error.next"].exists)
        activate(app.buttons["player.error.close"])
        activate(app.buttons["ホームに戻る"])
        XCTAssertTrue(app.buttons["home.chooseFolder"].waitForExistence(timeout: 5))
    }
    func testPreparationTimeoutRemainsStopped() throws {
        let app = try launch(folder: "slow-media"); defer { app.terminate() }
        choose(app, "Slow OP.mp4")
        XCTAssertTrue(app.buttons["player.error.retry"].waitForExistence(timeout: 45))
        state(app, "Slow OP.mp4", playing: false)
        XCTAssertTrue(app.staticTexts["再試行位置: 0.0秒"].exists)
        XCUIRemote.shared.press(.menu)
        state(app, "Slow OP.mp4", playing: false)
        XCTAssertFalse(app.buttons["dlna.cancel"].exists)
    }
    private func isFocused(_ element: XCUIElement) -> Bool {
        guard element.exists else { return false }
        if element.hasFocus || element.descendants(matching: .button).allElementsBoundByIndex.contains(where: { $0.hasFocus }) { return true }
        let cell = XCUIApplication().cells.containing(.button, identifier: element.label).firstMatch
        return cell.exists && cell.hasFocus
    }
    private func activate(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 45))
        for _ in 0..<45 {
            if isFocused(element) { XCUIRemote.shared.press(.select); return }
            let app = XCUIApplication()
            let current = (app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex + app.textFields.allElementsBoundByIndex)
                .first { $0.hasFocus }
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
