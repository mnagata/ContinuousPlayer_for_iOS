import XCTest

final class Stage5TVChromeUITests: XCTestCase {
    private func player(audio: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state", "-dlna.lastServerAddress",
            "http://127.0.0.1:18765/" + (audio ? "audio.xml" : "description.xml")]
        app.launch()
        activate(app.buttons["home.chooseFolder"])
        activate(app.buttons["saved.addFolder"])
        activate(app.buttons["saved.source.dlna"])
        activate(app.buttons["Fixture NAS"])
        activate(app.buttons["dlna.registerFolder"])
        activate(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).firstMatch)
        activate(app.buttons[audio ? "音声.01から連続再生" : "作品 OP.mp4から連続再生"])
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '|playing|'"), object: app.staticTexts["player.sessionState"])
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 15), .completed)
        return app
    }
    func testTopAndBottomControlsAndInformation() {
        let app = player(); defer { app.terminate() }
        XCUIRemote.shared.press(.playPause)
        let play = app.buttons["player.toggle"]
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        let home = app.buttons["ホームに戻る"], list = app.buttons["player.chooseFolder"], info = app.buttons["メディア情報"]
        XCTAssertLessThan(home.frame.midX, list.frame.midX)
        XCTAssertLessThan(list.frame.midX, info.frame.midX)
        XCTAssertLessThan(info.frame.midY, app.frame.midY)
        let transport = [app.buttons["前のファイル"], app.buttons["10秒戻す"], play, app.buttons["10秒進める"], app.buttons["次のファイル"]]
        for button in transport { XCTAssertTrue(button.exists); XCTAssertGreaterThan(button.frame.midY, app.frame.midY) }
        for index in 1..<transport.count { XCTAssertLessThan(transport[index - 1].frame.midX, transport[index].frame.midX) }
        XCTAssertFalse(transport[0].isEnabled)
        capture("stage5-tv-paused")
        activate(info)
        XCTAssertTrue(app.staticTexts["映像・音声形式"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.menu)
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dlna.cancel"].exists)
    }
    func testAudioOnlyKeepsControlsDuringPlayback() {
        let app = player(audio: true); defer { app.terminate() }
        XCTAssertTrue(app.buttons["player.toggle"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["ホームに戻る"].exists)
        XCTAssertFalse(app.buttons["前のファイル"].isEnabled)
        XCTAssertFalse(app.buttons["次のファイル"].isEnabled)
        XCTAssertEqual(app.buttons["player.toggle"].label, "一時停止")
        capture("stage5-tv-audio-playing")
    }
    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    private func focused(_ e: XCUIElement) -> Bool {
        guard e.exists else { return false }
        if e.hasFocus || e.descendants(matching: .button).allElementsBoundByIndex.contains(where: { $0.hasFocus }) { return true }
        let cell = XCUIApplication().cells.containing(.button, identifier: e.label).firstMatch
        return cell.exists && cell.hasFocus
    }
    private func activate(_ e: XCUIElement) {
        XCTAssertTrue(e.waitForExistence(timeout: 20))
        for _ in 0..<45 {
            if focused(e) { XCUIRemote.shared.press(.select); return }
            let app = XCUIApplication()
            let current = (app.buttons.allElementsBoundByIndex + app.cells.allElementsBoundByIndex + app.textFields.allElementsBoundByIndex).first { $0.hasFocus }
            if let current {
                let dx = e.frame.midX - current.frame.midX, dy = e.frame.midY - current.frame.midY
                if abs(dy) > max(10, current.frame.height / 2) { XCUIRemote.shared.press(dy < 0 ? .up : .down) }
                else { XCUIRemote.shared.press(dx < 0 ? .left : .right) }
            } else { XCUIRemote.shared.press(.down) }
        }
        print(XCUIApplication().debugDescription); XCTFail("Could not focus \(e.label)")
    }
}
