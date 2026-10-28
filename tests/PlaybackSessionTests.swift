import AVFoundation
import Foundation

@main struct PlaybackSessionTests {
    @MainActor static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        precondition(condition(), message)
    }

    @MainActor static func main() async throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1])
        let files = ["Fixture OP.mp4", "Fixture ED.mp4"].map { folder.appendingPathComponent($0) }
        let session = PlaybackSessionCoordinator()
        let engine = session.playback
        engine.adjustVolume(by: -100)
        engine.setPlaylist(files)
        engine.commitSelection(files[0])
        try await wait("initial playback") { !engine.isLoading && engine.player.rate > 0 }
        _ = await engine.player.seek(to: CMTime(seconds: 30, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        let originalItem = engine.player.currentItem
        let originalTime = engine.player.currentTime().seconds
        let browser = engine.beginPresentation()
        precondition(!engine.state.wantsToPlay && engine.player.rate == 0)
        engine.move(1)
        engine.seek(by: 10)
        engine.resume()
        precondition(engine.state.currentURL == files[0] && !engine.state.wantsToPlay)
        engine.endPresentation(browser)
        try await wait("cancel resumes original") { engine.player.rate > 0 }
        precondition(engine.player.currentItem === originalItem)
        precondition(abs(engine.player.currentTime().seconds - originalTime) < 0.3)
        engine.pause()
        let paused = engine.beginPresentation()
        engine.endPresentation(paused)
        precondition(!engine.state.wantsToPlay && engine.player.rate == 0)
        print("PASS: playing/paused cancellation preserves item, queue and position; modal transport isolation")

        for interruption in 0..<4 {
            engine.resume()
            let info = engine.beginPresentation()
            switch interruption {
            case 0: session.setSceneAllowsPlayback(false); session.setSceneAllowsPlayback(true)
            case 1: engine.setInterrupted(true); engine.setInterrupted(false)
            case 2: engine.outputDisconnected()
            default: session.setBlocked("sleep", true); session.setBlocked("sleep", false)
            }
            engine.endPresentation(info)
            precondition(!engine.state.wantsToPlay && engine.player.rate == 0)
        }
        engine.resume()
        let outer = engine.beginPresentation()
        let inner = engine.beginPresentation()
        engine.endPresentation(inner)
        precondition(!engine.state.wantsToPlay)
        engine.endPresentation(outer)
        precondition(engine.state.wantsToPlay)
        print("PASS: interruption history survives return to active; nested UI cannot resume early")

        let eof = engine.beginPresentation()
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: originalItem)
        engine.endPresentation(eof)
        try await Task.sleep(for: .milliseconds(100))
        precondition(engine.state.currentURL == files[0])
        let hidden = engine.beginPresentation()
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: originalItem)
        try await Task.sleep(for: .milliseconds(100))
        precondition(engine.state.currentURL == files[0])
        engine.endPresentation(hidden)
        print("PASS: queued and suspended end notifications cannot advance the hidden playlist")

        for file in [files[0], files[1]] {
            let presentation = engine.beginPresentation()
            engine.commitSelection(file)
            engine.endPresentation(presentation)
            try await wait("selection prepares and starts") { !engine.isLoading && engine.player.rate > 0 }
            precondition(engine.state.currentURL == file && engine.player.currentTime().seconds < 1)
            engine.pause()
        }
        engine.commitSelection(files[0])
        let preparing = engine.beginPresentation()
        try await wait("preparation completes under presentation") { !engine.isLoading }
        precondition(engine.player.rate == 0 && !engine.state.wantsToPlay)
        engine.endPresentation(preparing)
        try await wait("cancel prepared selection resumes") { engine.player.rate > 0 }
        print("PASS: same/different selection starts at zero; preparation cannot start behind UI")

        let obsolete = engine.beginPresentation()
        session.end()
        engine.setPlaylist(files)
        engine.commitSelection(files[1], autoplay: false)
        engine.endPresentation(obsolete)
        try await wait("replacement paused item prepares") { !engine.isLoading }
        precondition(!engine.state.wantsToPlay && engine.state.currentURL == files[1])
        let denied = engine.beginPresentation()
        engine.accessFailed()
        engine.endPresentation(denied)
        precondition(!engine.state.wantsToPlay && engine.needsFolderSelection)
        session.setBlocked("sleep", true)
        session.setBlocked("hidden", true)
        session.setBlocked("sleep", false)
        engine.setPlaylist(files)
        engine.commitSelection(files[0])
        session.setBlocked("hidden", false)
        precondition(!engine.state.wantsToPlay)
        print("PASS: obsolete restoration, revoked access and overlapping blockers do not restart playback")

        let corrupt = folder.appendingPathComponent("Corrupt OP.mp4")
        engine.setPlaylist([corrupt] + files)
        engine.commitSelection(corrupt)
        try await wait("chosen corrupt item reports an error") { engine.error != nil }
        precondition(engine.state.currentURL == corrupt && !engine.state.wantsToPlay)
        engine.setPlaylist(files)
        engine.commitSelection(files[0])
        let closing = engine.beginPresentation()
        session.end()
        engine.endPresentation(closing)
        try await Task.sleep(for: .milliseconds(200))
        precondition(engine.player.currentItem == nil && !engine.isLoading && !engine.state.wantsToPlay)
        print("PASS: selected preparation failure stays selected; close invalidates pending preparation and restore")

        let local = MediaLibrary(playback: engine)
        await local.open(folder, persist: false, loadPlaylist: false)
        await local.playFromSelection(files[0])
        try await wait("local selected file starts") { !engine.isLoading && engine.player.rate > 0 }
        _ = await engine.player.seek(to: CMTime(seconds: 30, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        let localItem = engine.player.currentItem
        let localBrowser = engine.beginPresentation()
        _ = try await MediaScanner.browse(folder.appendingPathComponent("Other Folder"), within: folder)
        engine.endPresentation(localBrowser)
        precondition(engine.player.currentItem === localItem && engine.state.wantsToPlay)
        precondition(abs(engine.player.currentTime().seconds - 30) < 0.3)
        engine.pause()
        await local.playFromSelection(files[0])
        try await wait("same local file explicitly starts") { !engine.isLoading && engine.player.rate > 0 }
        precondition(engine.player.currentTime().seconds < 1)
        local.stop()
        precondition(engine.player.currentItem == nil && !engine.state.wantsToPlay)
        print("PASS: local parent enumeration, other-folder browsing, 30-second cancel and same-file autoplay")
    }
}
