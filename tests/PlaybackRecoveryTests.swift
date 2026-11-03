import AVFoundation
import Foundation

@MainActor private final class SeekGate {
    var hold = false
    var pending: CheckedContinuation<Bool, Never>?
    func seek(_ player: AVPlayer, to time: CMTime) async -> Bool {
        if hold { return await withCheckedContinuation { pending = $0 } }
        return await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    func complete() { pending?.resume(returning: true); pending = nil }
}

@MainActor private final class PrerollGate {
    var interrupted = false
    var hold = false
    var pending: CheckedContinuation<Bool, Never>?

    func preroll(_ player: AVPlayer) async -> Bool {
        if hold { return await withCheckedContinuation { pending = $0 } }
        if interrupted { return false }
        return await player.preroll(atRate: 1)
    }

    func complete() { pending?.resume(returning: false); pending = nil }
}

@main struct PlaybackRecoveryTests {
    @MainActor static func wait(_ message: String, _ predicate: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !predicate(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        precondition(predicate(), message)
    }
    @MainActor static func fail(_ engine: PlaybackController, access: Bool = false) async throws {
        let item = engine.player.currentItem!
        let error = access ? NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
            : NSError(domain: NSURLErrorDomain, code: URLError.networkConnectionLost.rawValue)
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: item,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: error])
        try await wait("failure is surfaced") { engine.failure != nil }
    }
    @MainActor static func main() async throws {
        let base = URL(string: CommandLine.arguments[1])!
        let folder = URL(fileURLWithPath: CommandLine.arguments[2])
        let files = ["Fixture OP.mp4", "Fixture ED.mp4"].map { folder.appendingPathComponent($0) }
        try await testInterruptedPreroll(playlists: [files,
            ["op", "ed"].map { base.appendingPathComponent("media/\($0).mp4") }])
        let engine = PlaybackController()
        engine.adjustVolume(by: -100)
        engine.setPlaylist(files)
        engine.commitSelection(files[0], autoplay: false)
        try await wait("local item prepares with seekable range") { !engine.isLoading && engine.canSeek }
        engine.seek(by: 30)
        try await wait("seek completes and is confirmed") { !engine.isSeeking && abs(engine.confirmedSeconds - 30) < 0.1 }
        try await fail(engine)
        let failed = engine.failure!
        precondition(failed.url == files[0] && abs(failed.seconds - 30) < 0.1)
        precondition(engine.state.files == files && engine.state.currentURL == files[0] && !engine.state.wantsToPlay)
        precondition(engine.player.currentItem == nil && engine.showsFailure && !engine.canSeek)
        engine.dismissFailure()
        let modal = engine.beginPresentation()
        engine.endPresentation(modal)
        precondition(!engine.showsFailure && engine.failure?.id == failed.id && !engine.state.wantsToPlay)
        engine.setActive(false); engine.setActive(true)
        precondition(!engine.state.wantsToPlay && engine.failure?.id == failed.id)
        engine.retry()
        try await wait("retry seeks before autoplay") { !engine.isLoading && engine.player.rate > 0 }
        precondition(engine.state.currentURL == files[0] && abs(engine.player.currentTime().seconds - 30) < 1)
        engine.pause()
        try await fail(engine)
        engine.nextAfterFailure()
        try await wait("explicit error next starts at zero") { !engine.isLoading && engine.player.rate > 0 }
        precondition(engine.state.currentURL == files[1] && engine.player.currentTime().seconds < 1)
        engine.stopSession()
        print("PASS: failure retains item/queue/30-second position; close and return never resume; retry restores; explicit next autoplays at zero")

        let gate = SeekGate()
        let seeking = PlaybackController(seek: { await gate.seek($0, to: $1) })
        seeking.setPlaylist(files)
        seeking.commitSelection(files[0], autoplay: false)
        try await wait("seek race fixture prepares") { !seeking.isLoading && seeking.canSeek }
        seeking.seek(by: 30)
        try await wait("baseline position confirmed") { !seeking.isSeeking && abs(seeking.confirmedSeconds - 30) < 0.1 }
        gate.hold = true
        seeking.seek(by: 10)
        try await wait("seek is deliberately unfinished") { gate.pending != nil }
        try await fail(seeking)
        precondition(abs(seeking.failure!.seconds - 30) < 0.1, "An unconfirmed 40-second target is not a recovery point")
        gate.hold = false; gate.complete()
        seeking.retry()
        seeking.setInterrupted(true); seeking.setInterrupted(false)
        try await wait("retry prepares despite interruption") { !seeking.isLoading }
        precondition(!seeking.state.wantsToPlay && seeking.player.rate == 0)
        precondition(abs(seeking.player.currentTime().seconds - 30) < 0.1, "Cancelled seek callback cannot corrupt retry")
        let presented = seeking.beginPresentation()
        try await fail(seeking, access: true)
        seeking.endPresentation(presented)
        precondition(seeking.needsFolderSelection && !seeking.state.wantsToPlay && seeking.failure?.recovery == .localAccess)
        seeking.dismissFailure()
        seeking.retry()
        try await wait("explicit retry recovers restored local access") { !seeking.isLoading && seeking.player.rate > 0 }
        seeking.stopSession()
        print("PASS: unfinished and obsolete seek results never replace confirmed recovery time; interruption and reauthorization require explicit retry")

        let remote = PlaybackController()
        let urls = ["corrupt", "missing", "op"].map { base.appendingPathComponent("media/\($0).mp4") }
        remote.setPlaylist(urls)
        remote.select(urls[0])
        try await wait("corrupt media fails without auto-skip") { remote.failure != nil }
        precondition(remote.state.currentURL == urls[0] && remote.failure?.seconds == 0 && !remote.state.wantsToPlay)
        let id = remote.failure!.id
        try await Task.sleep(for: .milliseconds(300))
        precondition(remote.failure?.id == id, "No automatic retry")
        remote.nextAfterFailure()
        try await wait("404 stops on selected item") { remote.failure != nil }
        precondition(remote.state.currentURL == urls[1] && remote.failure?.recovery == .network)
        remote.nextAfterFailure()
        try await wait("explicit next reaches playable media") { !remote.isLoading && remote.player.rate > 0 }
        let current = remote.state.currentURL
        remote.checkStall(elapsed: .seconds(3))
        precondition(remote.isBuffering)
        remote.checkStall(elapsed: .seconds(31))
        precondition(remote.failure != nil && remote.state.currentURL == current && !remote.state.wantsToPlay)
        remote.retry()
        try await wait("network retry prepares") { !remote.isLoading && remote.player.rate > 0 }
        remote.stopSession()
        print("PASS: actual corrupt/HTTP 404 failures and a deterministic 30-second stall stop on current item; recovery is explicit")

        // Real timeout task with a reduced test deadline against delayed HTTP.
        // Production's default remains 30 seconds.
        let timeout = PlaybackController(preparationLimit: .milliseconds(200))
        let slow = base.appendingPathComponent("media/slow.mp4")
        timeout.setPlaylist([slow, urls[2]])
        timeout.select(slow)
        try await wait("preparation deadline fails") { timeout.failure != nil }
        precondition(timeout.state.currentURL == slow && !timeout.state.wantsToPlay && timeout.failure?.seconds == 0)
        timeout.dismissFailure(); timeout.setActive(false); timeout.setActive(true)
        try await Task.sleep(for: .milliseconds(300))
        precondition(!timeout.state.wantsToPlay && timeout.state.currentURL == slow)
        timeout.stopSession()
        print("PASS: real preparation timeout task (200 ms test deadline) stops without skip or background retry")

        engine.setPlaylist(files)
        engine.commitSelection(files[0], autoplay: false)
        try await wait("boundary fixture prepares") { !engine.isLoading && engine.canSeek }
        engine.seek(by: -10)
        try await wait("negative seek confirms zero") { !engine.isSeeking }
        precondition(engine.player.currentTime().seconds < 0.1)
        engine.seek(by: 100)
        try await wait("known-length crossing moves to next paused") { engine.state.currentURL == files[1] && !engine.isLoading }
        precondition(!engine.state.wantsToPlay && engine.player.currentTime().seconds < 0.1)
        engine.seek(by: 30)
        try await wait("final-item seek confirms") { !engine.isSeeking && engine.confirmedSeconds >= 30 }
        engine.seek(by: 100)
        precondition(engine.state.currentURL == files[1] && abs(engine.player.currentTime().seconds - 30) < 0.1)
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: engine.player.currentItem!)
        try await wait("natural final end remains ended") { engine.state.ended }
        engine.resume()
        try await wait("play after end restarts final item at zero") { !engine.isLoading && engine.player.rate > 0 }
        precondition(engine.state.currentURL == files[1] && engine.player.currentTime().seconds < 1)
        engine.stopSession()
        print("PASS: real AVPlayer zero/cross-end/final-item boundaries and final end restart")

        let audioURL = URL(fileURLWithPath: CommandLine.arguments[3])
        let audio = await MediaInfo.load(audioURL, asset: AVURLAsset(url: audioURL))
        precondition(audio.video == "映像なし" && audio.audio.contains("kHz"))
        precondition(audio.isAudioOnly && audio.hasVideo == false && audio.hasAudio == true)
        let videoURL = URL(fileURLWithPath: CommandLine.arguments[4])
        let videoOnly = await MediaInfo.load(videoURL, asset: AVURLAsset(url: videoURL))
        precondition(videoOnly.audio == "音声なし" && videoOnly.video != "取得できません")
        precondition(!videoOnly.isAudioOnly && videoOnly.hasVideo == true && videoOnly.hasAudio == false)
        let corruptURL = folder.appendingPathComponent("Corrupt OP.mp4")
        let corrupt = await MediaInfo.load(corruptURL, asset: AVURLAsset(url: corruptURL))
        precondition(corrupt.video == "取得できません" && corrupt.audio == "取得できません")
        precondition(!corrupt.isAudioOnly && corrupt.hasVideo == nil && corrupt.hasAudio == nil)
        precondition(corrupt.size != "取得できません", "File information survives failed track loading")
        #if os(macOS)
        precondition(AudioOutputInfo.current().device == "未対応", "Native test host lacks the AVAudioSession API")
        #endif
        print("PASS: no video track, unavailable track data, independent file size and unsupported API are distinct")
        print("Stage 3 playback recovery tests passed")
    }

    @MainActor private static func testInterruptedPreroll(playlists: [[URL]]) async throws {
        for files in playlists {
            let gate = PrerollGate()
            let engine = PlaybackController(preroll: { await gate.preroll($0) })
            engine.adjustVolume(by: -100)
            engine.setPlaylist(files)
            engine.commitSelection(files[0])
            try await wait("first item starts normally") { !engine.isLoading && engine.player.rate > 0 }

            gate.interrupted = true
            NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: engine.player.currentItem!)
            try await wait("next item completes preparation") {
                engine.state.currentURL == files[1] && !engine.isLoading
            }
            precondition(engine.failure == nil,
                         "An interrupted preroll on a healthy next item must not become a media failure")
            try await wait("next item plays despite interrupted preroll") { engine.player.currentTime().seconds > 0 }
            precondition(engine.state.wantsToPlay && engine.state.currentURL == files[1])

            engine.pause(); engine.move(-1)
            try await wait("paused replacement completes preparation") { !engine.isLoading }
            precondition(engine.failure == nil && !engine.state.wantsToPlay && engine.player.rate == 0)

            gate.hold = true
            engine.resume(); engine.move(1)
            try await wait("preroll is pending before interruption") { gate.pending != nil }
            engine.setInterrupted(true)
            gate.complete()
            try await wait("interrupted preparation finishes") { !engine.isLoading }
            precondition(engine.failure == nil && !engine.state.wantsToPlay && engine.player.rate == 0,
                         "Preroll fallback must not undo an audio interruption")
            engine.setInterrupted(false)

            engine.move(-1)
            try await wait("old preroll waits before replacement") { gate.pending != nil }
            gate.hold = false
            engine.move(1)
            try await wait("replacement prepares independently") { !engine.isLoading }
            let item = engine.player.currentItem
            gate.complete()
            try await Task.sleep(for: .milliseconds(100))
            precondition(engine.failure == nil && engine.player.currentItem === item && engine.state.currentURL == files[1],
                         "An obsolete preroll completion cannot fail or replace the new item")

            gate.hold = true
            engine.move(-1)
            try await wait("preroll is pending before actual failure") { gate.pending != nil }
            try await fail(engine)
            let failureID = engine.failure!.id
            gate.complete()
            try await Task.sleep(for: .milliseconds(100))
            precondition(engine.failure?.id == failureID && engine.player.currentItem == nil && !engine.state.wantsToPlay,
                         "Preroll fallback must not clear a real playback failure")

            engine.stopSession()
        }
        print("PASS: interrupted preroll permits local/HTTP next-item playback and paused preparation; interruptions, obsolete callbacks and real failures remain guarded")
    }
}
