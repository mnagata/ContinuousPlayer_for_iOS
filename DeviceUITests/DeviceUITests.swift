import XCTest

final class DeviceUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
        app.terminate()
    }

    private func launchFixtures(extra: [String] = []) {
        app.launchArguments = ["--ui-fixtures"] + extra
        app.launch()
        XCTAssertTrue(app.buttons["1、実機テスト OP.wavから再生"].waitForExistence(timeout: 15))
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPlaybackRotationAndBackground() {
        launchFixtures()
        app.buttons["1、実機テスト OP.wavから再生"].tap()
        XCTAssertTrue(app.buttons["一時停止"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["一時停止"].firstMatch.tap()
        XCTAssertTrue(app.buttons["ホームに戻る"].waitForExistence(timeout: 5))
        capture("ipad-paused-portrait")
        app.buttons["次のファイル"].tap()
        XCTAssertTrue(app.staticTexts["実機テスト ED.wav"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["一時停止"].firstMatch.exists)
        XCUIDevice.shared.orientation = .landscapeLeft
        app.buttons["メディア情報"].tap()
        XCTAssertTrue(app.navigationBars["メディア情報"].waitForExistence(timeout: 5))
        capture("ipad-info-landscape")
        app.buttons["閉じる"].tap()
        capture("ipad-paused-landscape")
        app.buttons["再生"].firstMatch.tap()
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["ホームに戻る"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["一時停止"].firstMatch.exists)
        capture("ipad-background-return-paused")
        app.buttons["ホームに戻る"].tap()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 5))
        capture("ipad-home")
    }

    func testNaturalAdvanceAndEnd() {
        launchFixtures()
        app.buttons["3、実機テスト OP2.wavから再生"].tap()
        XCTAssertTrue(app.staticTexts["最後まで再生しました"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["実機テスト ED2.wav"].firstMatch.exists)
        XCTAssertFalse(app.buttons["次のファイル"].isEnabled)
        capture("ipad-playlist-ended")
    }

    func testLargeTextControls() {
        launchFixtures(extra: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"])
        app.buttons["1、実機テスト OP.wavから再生"].tap()
        app.buttons["一時停止"].firstMatch.tap()
        XCTAssertTrue(app.buttons["ホームに戻る"].waitForExistence(timeout: 5))
        capture("ipad-largest-text-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["メディア情報"].isHittable)
        capture("ipad-largest-text-landscape")
        app.buttons["ホームに戻る"].tap()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 5))
    }

    func testGestureAndSeekBoundary() {
        launchFixtures()
        app.buttons["1、実機テスト OP.wavから再生"].tap()
        let center = app.buttons["一時停止"].firstMatch
        XCTAssertTrue(center.waitForExistence(timeout: 5))
        center.doubleTap()
        XCTAssertTrue(app.buttons["ホームに戻る"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["一時停止"].firstMatch.exists)
        // Swipe only within the video area, avoiding the toolbar and transport.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.staticTexts["実機テスト ED.wav"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["一時停止"].firstMatch.exists)
        app.buttons["次のファイル"].tap()
        XCTAssertTrue(app.staticTexts["実機テスト OP2.wav"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["10秒進める"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["実機テスト ED2.wav"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["一時停止"].firstMatch.exists)
        app.buttons["10秒進める"].firstMatch.tap()
        XCTAssertFalse(app.staticTexts["最後まで再生しました"].exists)
        app.buttons["10秒戻す"].firstMatch.tap()
        capture("ipad-gesture-seek-boundary")
    }

    func testLocalFolderSelectionAndBookmarkRestore() {
        launchFixtures(extra: ["--ui-bookmark-tests"])
        app.buttons["フォルダーを選び直す"].tap()
        XCTAssertTrue(app.staticTexts["picker.folderPrompt"].waitForExistence(timeout: 10))
        let open = app.buttons.matching(NSPredicate(format: "label == 'Open' OR label == '開く'")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        XCTAssertTrue(app.staticTexts["home.authorizationStatus"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["home.authorizeFolder"].exists)
        XCTAssertFalse(app.buttons["一時停止"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["picker.filePrompt"].exists)
        app.terminate()
        app.launchArguments = ["--ui-bookmark-tests"]
        app.launch()
        XCTAssertTrue(app.staticTexts["home.authorizationStatus"].waitForExistence(timeout: 10))
        app.buttons["home.select"].tap()
        XCTAssertTrue(app.staticTexts["picker.filePrompt"].waitForExistence(timeout: 10))
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", "実機テスト OP", "実機テスト OP")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 15))
        file.tap()
        XCTAssertTrue(app.buttons["一時停止"].firstMatch.waitForExistence(timeout: 10))
        capture("separate-authorization-restored-playback")
    }

    func testSelectFileInCurrentFolder() {
        launchFixtures(extra: ["--ui-bookmark-tests"])
        app.buttons["1、実機テスト OP.wavから再生"].tap()
        XCTAssertTrue(app.buttons["一時停止"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["一時停止"].firstMatch.tap()
        XCTAssertTrue(app.buttons["ホームに戻る"].waitForExistence(timeout: 5))
        app.buttons["ホームに戻る"].tap()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 5))
        app.buttons["home.select"].tap()
        XCTAssertTrue(app.staticTexts["picker.filePrompt"].waitForExistence(timeout: 10))
        let file = app.cells.matching(NSPredicate(format: "label CONTAINS %@ OR identifier CONTAINS %@", "実機テスト OP", "実機テスト OP")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        file.tap()
        XCTAssertTrue(app.buttons["一時停止"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["実機テスト OP.wav"].firstMatch.exists)
        capture("permitted-file-selection-playing")
    }

    func testReopenFilePickerInPlayingSubfolder() {
        launchFixtures(extra: ["--ui-bookmark-tests"])
        app.buttons["1、実機テスト OP.wavから再生"].tap()
        XCTAssertTrue(app.buttons["一時停止"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["一時停止"].firstMatch.tap()
        XCTAssertTrue(app.buttons["ホームに戻る"].waitForExistence(timeout: 5))
        app.buttons["folder"].tap()
        let subfolder = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH 'SecondPlaylist,' OR label BEGINSWITH 'SecondPlaylist,'")).firstMatch
        XCTAssertTrue(subfolder.waitForExistence(timeout: 20))
        subfolder.tap()
        let file = app.cells.matching(NSPredicate(format: "identifier CONTAINS %@ OR label CONTAINS %@", "別フォルダー OP", "別フォルダー OP")).firstMatch
        XCTAssertTrue(file.waitForExistence(timeout: 10))
        file.tap()
        XCTAssertTrue(app.buttons["一時停止"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["一時停止"].firstMatch.tap()
        XCTAssertTrue(app.buttons["ホームに戻る"].waitForExistence(timeout: 5))
        app.buttons["folder"].tap()
        XCTAssertTrue(file.waitForExistence(timeout: 20), "Reopen the playing subfolder, not the authorized parent")
        XCTAssertFalse(subfolder.exists)
        capture("reopened-current-subfolder")
        file.tap()
        XCTAssertTrue(app.buttons["一時停止"].firstMatch.waitForExistence(timeout: 10))
    }

    func testUSBPickerDiagnostics() throws {
        guard ProcessInfo.processInfo.environment["USB_PICKER_DIAGNOSTIC"] == "1" else {
            throw XCTSkip("Run explicitly with USB_PICKER_DIAGNOSTIC=1 on the connected device")
        }
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["home.select"].waitForExistence(timeout: 15))
        app.buttons["home.authorizeFolder"].tap()
        let open = app.buttons.matching(NSPredicate(format: "label == 'Open' OR label == '開く'")).firstMatch
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        open.tap()
        XCTAssertTrue(app.staticTexts["home.authorizationStatus"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["一時停止"].firstMatch.exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["home.authorizationStatus"].waitForExistence(timeout: 15))
        app.buttons["home.select"].tap()
        _ = app.cells.firstMatch.waitForExistence(timeout: 20)
        let mp4 = app.cells.matching(NSPredicate(format: "identifier ENDSWITH[c] ', mp4'")).firstMatch
        XCTAssertTrue(mp4.waitForExistence(timeout: 15))
        let selectedIdentifier = mp4.identifier
        print("USB_PICKER_SELECTED " + selectedIdentifier)
        mp4.tap()
        let started = app.buttons["一時停止"].firstMatch.waitForExistence(timeout: 20)
        capture("usb-picker-after-tap")
        XCTAssertTrue(started, "MP4 tap must start playback")
        app.buttons["一時停止"].firstMatch.tap()
        XCTAssertTrue(app.buttons["ホームに戻る"].waitForExistence(timeout: 5))
        app.buttons["folder"].tap()
        XCTAssertTrue(app.cells[selectedIdentifier].waitForExistence(timeout: 20),
                      "USB picker must reopen the directory containing the playing file")
        capture("usb-current-directory-reopened")
        app.buttons["folder.cancel"].tap()
    }

    func testFolderPickerCancel() {
        launchFixtures()
        app.buttons["フォルダーを選び直す"].tap()
        let cancel = app.buttons.matching(NSPredicate(format: "label == 'Cancel' OR label == 'キャンセル'")).firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        capture("ipad-folder-picker")
        cancel.tap()
        XCTAssertTrue(app.buttons["1、実機テスト OP.wavから再生"].waitForExistence(timeout: 5))
    }
}
