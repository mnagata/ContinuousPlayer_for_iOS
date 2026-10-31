import Foundation

@main struct PlaybackInputTests {
    static func main() {
        typealias Keys = PlaybackKeyboardInput
        precondition(Keys.command("left") == .previous && Keys.command("right") == .next)
        precondition(Keys.command("up") == .backward && Keys.command("down") == .forward)
        precondition(Keys.command("left", shift: true) == .backward && Keys.command("right", shift: true) == .forward)
        precondition(Keys.command(" ") == .toggle && Keys.command("return") == .toggle)
        precondition(Keys.command("escape") == .browse && Keys.command("O") == .browse)
        precondition(Keys.command("I") == .info && Keys.command("H") == .home)
        for target: Keys.Target in [.controls, .text, .modal, .list] {
            for key in ["left", "right", "up", "down", " ", "return", "escape", "i", "o", "h"] {
                precondition(Keys.command(key, target: target) == nil, "Only the video owns playback keys")
            }
        }
        precondition(Keys.command("right", repeating: true) == nil)
        precondition(Keys.command("h", modified: true) == nil)
        print("PASS: keyboard mapping, shifted seek, single down and OS/text/modal/control priority")

        var touch = PlaybackTouchInput()
        func point(_ x: Double, _ y: Double = 10) -> CGPoint { CGPoint(x: x, y: y) }
        touch.begin(at: point(250), time: 0, source: .direct)
        precondition(touch.end(at: point(250), time: 0.02, width: 300) == .forward)
        touch.begin(at: point(250), time: 0.1, source: .direct)
        precondition(touch.end(at: point(250), time: 0.12, width: 300) == nil)
        touch.begin(at: point(150), time: 0.2, source: .direct)
        precondition(touch.end(at: point(150), time: 0.22, width: 300) == .toggle, "Different regions stay independent")
        touch.begin(at: point(150), time: 0.6, source: .direct)
        precondition(touch.end(at: point(150), time: 0.62, width: 300) == .toggle)
        touch.begin(at: point(250), time: 1, source: .direct)
        precondition(touch.end(at: point(180), time: 1.2, width: 300) == .next)
        touch.begin(at: point(50), time: 2, source: .direct)
        precondition(touch.end(at: point(120), time: 2.2, width: 300) == .previous)
        touch.begin(at: point(250), time: 3, source: .direct)
        precondition(touch.end(at: point(180, 60), time: 3.2, width: 300) == nil, "Reject diagonal motion")
        touch.begin(at: point(250), time: 4, source: .direct)
        precondition(touch.end(at: point(181), time: 4.2, width: 300) == nil, "Reject a short drag, not a tap")
        touch.begin(at: point(250), time: 5, source: .direct)
        touch.begin(at: point(20), time: 5.01, source: .direct)
        precondition(touch.end(at: point(150), time: 5.2, width: 300) == nil)
        touch.begin(at: point(250), time: 6, source: .direct)
        precondition(touch.end(at: point(250), time: 7, width: 300) == nil, "Long hold is not a tap")
        print("PASS: immediate direct taps, 300 ms pair suppression, swipe boundaries, multi-touch and long-hold rejection")

        for x in [20.0, 150.0, 280.0] {
            touch.begin(at: point(x), time: 10, source: .pointer)
            precondition(touch.end(at: point(x), time: 10.1, width: 300) == .toggle)
            touch.begin(at: point(x), time: 10.2, source: .pointer)
            precondition(touch.end(at: point(x), time: 10.3, width: 300, clickCount: 2) == nil)
        }
        touch.begin(at: point(20), time: 11, source: .pointer, activeWindow: false)
        precondition(touch.end(at: point(20), time: 11.1, width: 300) == nil)
        touch.begin(at: point(250), time: 12, source: .pointer)
        precondition(touch.end(at: point(20), time: 12.2, width: 300) == nil)
        print("PASS: pointer positions all toggle; double-click, activation click and drag never seek or skip")

        var remote = TVDirectionalInput()
        remote.touchBegan()
        precondition(remote.press(1, command: .next) == .next)
        precondition(remote.press(1, command: .next) == nil)
        remote.release(1)
        precondition(remote.touchEnded(command: .next) == nil, "One press plus its touch is one action")
        precondition(remote.press(2, command: .previous) == .previous)
        remote.release(2)
        precondition(remote.press(3, command: .previous) == .previous, "No blanket time suppression")
        remote.release(3)
        remote.touchBegan()
        precondition(remote.touchEnded(command: .forward) == .forward)
        print("PASS: remote physical-press ownership, correlated touch suppression and independent rapid input")

        let ids = (0..<30).map(String.init)
        let viewport = CGRect(x: 0, y: 0, width: 300, height: 250)
        let frames = (0..<5).map { CGRect(x: 0, y: Double($0 * 60), width: 300, height: 60) }
        let size = FileListInput.pageSize(frames: frames, viewport: viewport)
        precondition(size == 4)
        precondition(FileListInput.destination(ids: ids, selected: "2", offset: size) == "6")
        precondition(FileListInput.destination(ids: ids, selected: "0", offset: -size) == "0")
        precondition(FileListInput.destination(ids: ids, selected: "29", offset: size) == "29")
        precondition(FileListInput.destination(ids: [], selected: nil, offset: 1) == nil)
        print("PASS: viewport-based page size and non-wrapping list navigation")
    }
}
