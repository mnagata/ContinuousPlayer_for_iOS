import XCTest

/// Optional: copy the four existing real samples to Documents/RealSamples first.
final class RealMediaUITests: XCTestCase {
    func testRealVideoPresentation() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--ui-real-samples"]
        XCUIDevice.shared.orientation = .portrait
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        app.launch()
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '1、' AND label ENDSWITH 'から再生'")).firstMatch
        guard first.waitForExistence(timeout: 10) else {
            throw XCTSkip("Documents/RealSamples is not installed; copy the four real media samples to run this test.")
        }
        first.tap()
        XCTAssertTrue(app.buttons["一時停止"].firstMatch.waitForExistence(timeout: 10))
        // Wait for decoding rather than taking a screenshot immediately after selection.
        sleep(3)
        app.buttons["一時停止"].firstMatch.tap()
        for index in 1...4 {
            XCTAssertTrue(app.buttons["メディア情報"].waitForExistence(timeout: 5))
            let frame = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            frame.name = "ipad-real-video-\(index)"
            frame.lifetime = .keepAlways
            add(frame)
            app.buttons["メディア情報"].tap()
            XCTAssertTrue(app.navigationBars["メディア情報"].waitForExistence(timeout: 5))
            let info = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            info.name = "ipad-real-info-\(index)"
            info.lifetime = .keepAlways
            add(info)
            app.buttons["閉じる"].tap()
            if index < 4 {
                app.buttons["次のファイル"].tap()
                app.buttons["再生"].firstMatch.tap()
                sleep(3)
                app.buttons["一時停止"].firstMatch.tap()
                if index == 2 { XCUIDevice.shared.orientation = .landscapeLeft }
            }
        }
        XCTAssertFalse(app.buttons["次のファイル"].isEnabled)
    }
}
