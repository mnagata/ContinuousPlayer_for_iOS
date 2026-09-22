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
        precondition(state.failed() && state.currentURL == files[1])
        precondition(state.failed() && state.currentURL == files[2])
        precondition(!state.failed() && !state.wantsToPlay && state.currentURL == files[2])
        precondition(state.select(files[0]))
        precondition(state.failed())
        state.didProgress()
        precondition(state.consecutiveFailures == 0)
        precondition(state.failed())
        precondition(state.failed())
        precondition(!state.failed())
        precondition(state.select(files[4]))
        precondition(!state.failed())
        state.replace([])
        precondition(state.currentURL == nil && !state.wantsToPlay && !state.ended)
        print("Playback state tests passed")
    }
}
