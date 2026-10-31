import XCTest

final class Stage5ChromeUITests: XCTestCase {
    private func listing(resource: String = "description.xml") -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state", "--ui-dlna-direct-only",
            "-dlna.lastServerAddress", "http://127.0.0.1:18767/" + resource]
        app.launch()
        app.buttons["home.select"].tap()
        app.buttons["saved.addFolder"].tap()
        app.buttons["saved.source.dlna"].tap()
        let server = app.buttons["Fixture NAS"]
        XCTAssertTrue(server.waitForExistence(timeout: 15)); server.tap()
        app.buttons["dlna.registerFolder"].tap()
        let saved = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 10)); saved.tap()
        return app
    }
    private func state(_ app: XCUIApplication, playing: Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS 'presenting=false'",
            playing ? "|playing|" : "|paused|"), object: app.staticTexts["player.sessionState"])
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed)
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testPortraitLandscapeControlsAndStableVideoFrame() {
        XCUIDevice.shared.orientation = .portrait
        let app = listing(); defer { app.terminate(); XCUIDevice.shared.orientation = .portrait }
        let file = app.buttons["作品 OP.mp4から連続再生"]
        XCTAssertTrue(file.waitForExistence(timeout: 10)); file.tap()
        state(app, playing: true)
        let video = app.buttons["player.video"]
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        let playingFrame = video.frame
        app.typeKey(.space, modifierFlags: [])
        state(app, playing: false)
        XCTAssertEqual(video.frame, playingFrame, "Showing controls must not resize the video")
        let home = app.buttons["ホームに戻る"], list = app.buttons["ファイル一覧"], info = app.buttons["メディア情報"]
        XCTAssertTrue(home.exists && list.exists && info.exists)
        XCTAssertLessThan(home.frame.midX, list.frame.midX)
        XCTAssertLessThan(list.frame.midX, info.frame.midX)
        XCTAssertEqual(home.frame.midY, info.frame.midY, accuracy: 2)
        XCTAssertLessThan(home.frame.midY, video.frame.midY)
        XCTAssertEqual(app.staticTexts["player.title"].label, "作品 OP.mp4", "Accessibility retains the original filename")
        XCTAssertEqual(app.staticTexts.matching(identifier: "player.title").count, 1)
        assertTransport(app, video: video)
        XCTAssertFalse(app.buttons["前のファイル"].isEnabled)
        XCTAssertTrue(app.buttons["次のファイル"].isEnabled)
        capture("stage5-portrait-paused")
        app.buttons["10秒進める"].tap()
        state(app, playing: false)
        info.tap()
        XCTAssertTrue(app.buttons["player.info.close"].waitForExistence(timeout: 5))
        app.typeKey("i", modifierFlags: [])
        state(app, playing: false)
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        state(app, playing: false)
        assertTransport(app, video: video)
        capture("stage5-landscape-paused")
        app.buttons["次のファイル"].tap()
        state(app, playing: false)
        XCTAssertFalse(app.buttons["次のファイル"].isEnabled)
        XCTAssertTrue(app.buttons["前のファイル"].isEnabled)
        app.buttons["player.toggle"].tap()
        state(app, playing: true)
        XCTAssertFalse(home.exists, "Touch/keyboard playback hides the menu")
    }
    func testOpaqueAudioResourceKeepsControlsWhilePlaying() {
        let app = listing(resource: "audio.xml"); defer { app.terminate() }
        let audio = app.buttons["音声.01から連続再生"]
        XCTAssertTrue(audio.waitForExistence(timeout: 10)); audio.tap()
        state(app, playing: true)
        let chrome = app.staticTexts["player.chromeState"]
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'audioOnly=true' AND label CONTAINS 'controls=true'"), object: chrome)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        XCTAssertTrue(app.buttons["ホームに戻る"].exists)
        XCTAssertTrue(app.buttons["player.toggle"].exists)
        capture("stage5-opaque-audio-playing")
        app.buttons["メディア情報"].tap()
        XCTAssertTrue(app.buttons["player.info.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS '映像なし'")).firstMatch.exists)
        app.typeKey("i", modifierFlags: [])
        state(app, playing: true)
        XCTAssertTrue(app.buttons["player.toggle"].exists)
    }
    private func assertTransport(_ app: XCUIApplication, video: XCUIElement) {
        let buttons = [app.buttons["前のファイル"], app.buttons["10秒戻す"], app.buttons["player.toggle"], app.buttons["10秒進める"], app.buttons["次のファイル"]]
        for button in buttons { XCTAssertTrue(button.exists); XCTAssertGreaterThan(button.frame.midY, video.frame.midY) }
        for index in 1..<buttons.count {
            XCTAssertLessThan(buttons[index - 1].frame.midX, buttons[index].frame.midX)
            XCTAssertEqual(buttons[0].frame.midY, buttons[index].frame.midY, accuracy: 2)
        }
    }
    func testDLNADisplayNamesCollisionBadgesAndOriginalInformation() {
        let app = listing(resource: "names.xml"); defer { app.terminate() }
        let file = app.buttons["作品.01 OP.mp4から連続再生"]
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["作品.01 OP.m4vから連続再生"].exists)
        XCTAssertTrue(app.staticTexts["形式 MP4"].exists)
        XCTAssertTrue(app.staticTexts["形式 M4V"].exists)
        XCTAssertTrue(app.staticTexts["作品.01 OP"].firstMatch.exists)
        capture("stage5-name-collision")
        file.tap(); state(app, playing: true)
        app.typeKey("i", modifierFlags: [])
        XCTAssertTrue(app.buttons["player.info.close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "作品.01 OP.mp4")).firstMatch.exists)
        capture("stage5-original-name-information")
        app.typeKey("i", modifierFlags: [])
        state(app, playing: true)
    }
}
