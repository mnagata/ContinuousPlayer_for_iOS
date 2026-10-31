import XCTest

/// Integration evidence supplements, rather than replaces, physical-device acceptance.
final class Stage6AcceptanceUITests: XCTestCase {
    private func player(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-bookmark-tests", "--ui-reset-registrations", "--ui-session-state",
            "--ui-dlna-direct-only", "-dlna.lastServerAddress", "http://127.0.0.1:18767/folders.xml"] + extra
        app.launch()
        tap(app.buttons["home.select"])
        tap(app.buttons["saved.addFolder"])
        tap(app.buttons["saved.source.dlna"])
        tap(app.buttons["Fixture NAS"])
        tap(app.buttons["dlna.folder.folder-0"])
        tap(app.buttons["dlna.registerFolder"])
        tap(saved(app))
        tap(app.buttons["dlna.folder.child-0"])
        tap(app.buttons["作品 OP.mp4から連続再生"])
        state(app, name: "作品 OP.mp4", playing: true)
        return app
    }

    func testThirtySecondCancellationAcrossFoldersAndInformation() {
        let app = player(); defer { app.terminate() }
        app.typeKey(.space, modifierFlags: [])
        state(app, name: "作品 OP.mp4", playing: false)
        for _ in 0..<3 {
            let target = seconds(app) + 10
            tap(app.buttons["10秒進める"])
            position(app, near: target, tolerance: 0.7)
        }
        XCTAssertEqual(seconds(app), 30, accuracy: 3)
        app.typeKey(.space, modifierFlags: [])
        state(app, name: "作品 OP.mp4", playing: true)
        let before = seconds(app)
        app.typeKey("o", modifierFlags: [])
        tap(app.buttons["selection.back"])
        tap(app.buttons["dlna.folder.child-1"])
        XCTAssertTrue(app.buttons["作品 ED.mp4から連続再生"].waitForExistence(timeout: 10))
        tap(app.buttons["dlna.cancel"])
        state(app, name: "作品 OP.mp4", playing: true)
        // Includes real playback between the observations and UI event delivery.
        position(app, near: before, tolerance: 4)
        print("STAGE6 playing cancel: before=\(before), after=\(seconds(app))")

        app.typeKey(.space, modifierFlags: [])
        state(app, name: "作品 OP.mp4", playing: false)
        let paused = seconds(app)
        app.typeKey("o", modifierFlags: [])
        XCTAssertTrue(app.buttons["作品 OP.mp4から連続再生"].waitForExistence(timeout: 10))
        tap(app.buttons["selection.back"])
        let selection = app.staticTexts["selection.inputState"]
        XCTAssertTrue(selection.label.contains("child-0"), "Return to the original folder, not the browsed sibling")
        tap(app.buttons["dlna.cancel"])
        state(app, name: "作品 OP.mp4", playing: false)
        position(app, near: paused, tolerance: 0.7)
        app.typeKey("i", modifierFlags: [])
        XCTAssertTrue(app.buttons["player.info.close"].waitForExistence(timeout: 5))
        app.typeKey("i", modifierFlags: [])
        state(app, name: "作品 OP.mp4", playing: false)
        position(app, near: paused, tolerance: 0.7)
        let evidence = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        evidence.name = "stage6-thirty-second-restoration"; evidence.lifetime = .keepAlways; add(evidence)
    }

    func testExplicitSelectionAndProcessRestartStartAtHome() {
        let app = player(); defer { app.terminate() }
        app.typeKey(.space, modifierFlags: [])
        state(app, name: "作品 OP.mp4", playing: false)
        tap(app.buttons["10秒進める"])
        position(app, near: 10, tolerance: 3)
        app.typeKey("o", modifierFlags: [])
        tap(app.buttons["作品 OP.mp4から連続再生"])
        state(app, name: "作品 OP.mp4", playing: true)
        XCTAssertLessThan(seconds(app), 4, "Same file selection starts over")
        app.typeKey(.space, modifierFlags: [])
        state(app, name: "作品 OP.mp4", playing: false)
        app.typeKey("o", modifierFlags: [])
        tap(app.buttons["作品 ED.mp4から連続再生"])
        state(app, name: "作品 ED.mp4", playing: true)
        XCTAssertLessThan(seconds(app), 4)
        app.terminate()
        app.launchArguments.removeAll { $0 == "--ui-reset-registrations" }
        app.launch()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["player.video"].exists)
        tap(app.buttons["home.select"])
        XCTAssertTrue(saved(app).waitForExistence(timeout: 10), "Registration survives process termination")
        XCTAssertFalse(app.buttons["player.video"].exists)
        tap(saved(app)); tap(app.buttons["dlna.folder.child-0"])
        tap(app.buttons["作品 OP.mp4から連続再生"])
        state(app, name: "作品 OP.mp4", playing: true)
        XCTAssertLessThan(seconds(app), 4)
    }

    func testBackgroundDuringListAndInformationAllowsManualResume() {
        let app = player(); defer { app.terminate() }
        for information in [false, true] {
            app.typeKey(information ? "i" : "o", modifierFlags: [])
            let close = app.buttons[information ? "player.info.close" : "dlna.cancel"]
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            tap(close)
            state(app, name: "作品 OP.mp4", playing: false)
            let play = app.buttons["player.toggle"]
            XCTAssertTrue(play.isEnabled, "Foreground return must permit explicit Play")
            let paused = seconds(app)
            tap(play)
            state(app, name: "作品 OP.mp4", playing: true)
            let progressed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.seconds(app) > paused + 0.2
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 10), .completed)
        }
    }

    func testManualPlayWhenAudioEndNotificationsNeverArrive() {
        let app = player(extra: ["--ui-audio-interruption-test"]); defer { app.terminate() }
        for information in [false, true] {
            app.typeKey(information ? "i" : "o", modifierFlags: [])
            let close = app.buttons[information ? "player.info.close" : "dlna.cancel"]
            XCTAssertTrue(close.waitForExistence(timeout: 10))
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
            app.activate()
            tap(close)
            state(app, name: "作品 OP.mp4", playing: false)
            // Deterministic version of the device log: foreground and unlocked,
            // but the audio-interrupted flag never receives an end event.
            tap(app.buttons["test.audioInterruption"])
            let blocked = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'allowed=false'"),
                object: app.staticTexts["player.sessionState"])
            XCTAssertEqual(XCTWaiter.wait(for: [blocked], timeout: 5), .completed)
            let play = app.buttons["player.toggle"]
            XCTAssertFalse(play.frame.intersects(app.buttons["test.audioInterruption"].frame), "Test controls must not intercept the real Play button")
            XCTAssertTrue(play.isEnabled, "User Play can request audio even while automatic playback remains blocked")
            let paused = seconds(app)
            tap(play)
            state(app, name: "作品 OP.mp4", playing: true)
            let progressed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                self.seconds(app) > paused + 0.2
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [progressed], timeout: 10), .completed)
        }
    }

    private func saved(_ app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saved.dlna.'")).firstMatch
    }
    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 15)); element.tap()
    }
    private func state(_ app: XCUIApplication, name: String, playing: Bool) {
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ AND label CONTAINS 'presenting=false'",
            "\(name)|\(playing ? "playing" : "paused")|"), object: app.staticTexts["player.sessionState"])
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
}
