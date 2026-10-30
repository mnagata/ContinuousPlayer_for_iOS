import Foundation

@main struct PlaybackTests {
    static func main() {
        let files = (0..<5).map { URL(fileURLWithPath: "/media/\($0).mp4") }
        var state = PlaybackState()
        state.replace(files)
        precondition(!state.move(1))
        precondition(!state.select(URL(fileURLWithPath: "/other/0.mp4")))
        precondition(state.select(files[2]))
        precondition(state.currentURL == files[2] && state.wantsToPlay)
        state.wantsToPlay = false
        precondition(state.move(1) && !state.wantsToPlay)
        precondition(state.move(-1) && state.currentURL == files[2])
        precondition(state.move(2))
        precondition(!state.move(1) && state.currentURL == files[4])
        state.finish()
        precondition(state.ended && !state.wantsToPlay)
        precondition(state.select(files[0]) && !state.ended)
        precondition(!state.move(-1))
        state.failed()
        precondition(state.currentURL == files[0] && !state.wantsToPlay && !state.ended)
        state.failed()
        precondition(state.currentURL == files[0] && !state.wantsToPlay)
        precondition(state.select(files[4]))
        state.failed()
        precondition(state.currentURL == files[4] && !state.wantsToPlay)
        state.replace([])
        precondition(state.currentURL == nil && !state.wantsToPlay && !state.ended)
        typealias Policy = PlaybackSeekPolicy
        precondition(Policy.action(current: 3, by: -10, duration: 90, ranges: [0...90], hasNext: true) == .position(0))
        precondition(Policy.action(current: 85, by: 10, duration: 90, ranges: [0...90], hasNext: true) == .next)
        precondition(Policy.action(current: 85, by: 10, duration: 90, ranges: [0...90], hasNext: false) == .none)
        precondition(Policy.action(current: 125, by: 10, duration: nil, ranges: [100...130], hasNext: true) == .position(130))
        precondition(Policy.action(current: 103, by: -10, duration: nil, ranges: [100...130], hasNext: true) == .position(100))
        precondition(Policy.action(current: 5, by: 10, duration: nil, ranges: [0...10, 20...30], hasNext: true) == .position(10))
        precondition(Policy.action(current: 5, by: 10, duration: 90, ranges: [], hasNext: true) == .none)
        precondition(Policy.action(current: .nan, by: 10, duration: nil, ranges: [0...90], hasNext: true) == .none)
        print("Playback state tests passed")
    }
}
