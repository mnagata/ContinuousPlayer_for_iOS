import AVFoundation
import Foundation

@MainActor private final class AudioActivationGate {
    var calls = 0
    var pending: CheckedContinuation<Void, Error>?
    func activate() async throws {
        calls += 1
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func complete(error: Error? = nil) {
        let continuation = pending; pending = nil
        if let error { continuation?.resume(throwing: error) }
        else { continuation?.resume() }
    }
}

/// Runs inside a 27+ Simulator process, using the real notification observer.
@main struct PlaybackAudioLifecycleTests {
    @MainActor static func main() async throws {
        guard #available(iOS 27, tvOS 27, *) else { fatalError("Requires a 27+ runtime") }
        let session = PlaybackSessionCoordinator()
        let engine = session.playback
        // Permission tests need a selected item, not a playing audio device.
        engine.stageSelection(URL(fileURLWithPath: "/test/selected.mp4"))
        precondition(engine.canResume)
        let presentation = engine.beginPresentation()
        engine.setInterrupted(true)
        let revision = engine.interruptionRevision
        precondition(!engine.canResume)
        // The old interruption-ended notification intentionally never arrives.
        NotificationCenter.default.post(name: AVAudioSession.resumptionRecommendationNotification,
                                        object: AVAudioSession.sharedInstance())
        engine.endPresentation(presentation)
        precondition(engine.canResume, "Resumption recommendation must restore manual Play without a legacy end event")
        precondition(!engine.state.wantsToPlay && engine.player.rate == 0)
        precondition(engine.interruptionRevision == revision, "Keep interruption history for modal restoration")
        print("PASS: missing legacy end restores manual Play without autoplay or losing interruption history")

        engine.setInterrupted(true)
        NotificationCenter.default.post(name: AVAudioSession.resumptionRecommendationNotification, object: NSObject())
        precondition(!engine.canResume, "Another session cannot clear this session's interruption")
        session.setSceneAllowsPlayback(false)
        session.setBlocked("protected-data", true)
        NotificationCenter.default.post(name: AVAudioSession.resumptionRecommendationNotification,
                                        object: AVAudioSession.sharedInstance())
        precondition(!engine.canResume, "Audio availability cannot override a locked/background scene")
        session.setSceneAllowsPlayback(true)
        precondition(!engine.canResume, "Protected data is still blocked")
        session.setBlocked("protected-data", false)
        precondition(engine.canResume && !engine.state.wantsToPlay)
        engine.setInterrupted(true)
        session.setSceneAllowsPlayback(false)
        session.setSceneAllowsPlayback(true)
        precondition(!engine.canResume, "Foreground alone cannot override an ongoing audio interruption")
        engine.setInterrupted(false)
        precondition(engine.canResume && !engine.state.wantsToPlay)
        print("PASS: other sessions, protected data, background and ongoing interruptions remain isolated")
        try await manualRecovery()
    }

    @MainActor private static func wait(_ message: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        precondition(condition(), message)
    }

    @MainActor private static func manualRecovery() async throws {
        let gate = AudioActivationGate()
        let engine = PlaybackController(activateAudio: { try await gate.activate() })
        let file = URL(fileURLWithPath: CommandLine.arguments[1])
        engine.setPlaylist([file]); engine.commitSelection(file, autoplay: false)
        try await wait("paused item prepares") { !engine.isLoading && engine.player.currentItem?.status == .readyToPlay }
        engine.seek(by: 30)
        try await wait("30-second seek") { !engine.isSeeking && abs(engine.player.currentTime().seconds - 30) < 0.7 }
        let item = engine.player.currentItem
        let original = engine.player.currentTime().seconds
        let presentation = engine.beginPresentation()
        engine.setInterrupted(true)
        engine.endPresentation(presentation)
        // Intentionally send neither interruption-ended nor resumption recommendation.
        precondition(!engine.canResume && engine.canRequestPlayback)
        engine.resume()
        precondition(gate.calls == 0 && !engine.state.wantsToPlay, "Automatic resume cannot request recovery")
        engine.resumeFromUserAction()
        try await wait("first explicit audio request") { gate.pending != nil }
        precondition(engine.isRequestingAudioRecovery && !engine.canRequestPlayback && !engine.state.wantsToPlay)
        engine.resumeFromUserAction()
        precondition(gate.calls == 1, "Repeated input cannot duplicate the pending request")
        gate.complete(error: NSError(domain: "test.audio-priority", code: 1))
        try await wait("rejected activation completes") { !engine.isRequestingAudioRecovery }
        precondition(!engine.state.wantsToPlay && !engine.allowsPlayback && engine.canRequestPlayback)
        precondition(engine.failure == nil && engine.player.currentItem === item)
        precondition(abs(engine.player.currentTime().seconds - original) < 0.7)
        engine.resumeFromUserAction()
        try await wait("second explicit audio request") { gate.pending != nil }
        gate.complete()
        try await wait("accepted activation resumes") { !engine.isRequestingAudioRecovery && engine.state.wantsToPlay }
        precondition(engine.allowsPlayback && engine.player.currentItem === item)
        precondition(abs(engine.player.currentTime().seconds - original) < 1)
        engine.pause()
        print("PASS: no end/recommendation event; explicit OS request, rejection/retry, deduplication and 30-second item preservation")

        for action in 0..<5 {
            engine.setInterrupted(true)
            engine.resumeFromUserAction()
            try await wait("pending recovery before cancellation") { gate.pending != nil }
            switch action {
            case 0: engine.pause()
            case 1:
                let modal = engine.beginPresentation(); engine.endPresentation(modal)
            case 2: engine.setActive(false); engine.setActive(true)
            case 3:
                engine.stopSession(); engine.setPlaylist([file]); engine.commitSelection(file, autoplay: false)
            default: engine.setInterrupted(true)
            }
            gate.complete()
            try await wait("stale recovery completes") { !engine.isRequestingAudioRecovery }
            precondition(!engine.state.wantsToPlay && engine.player.rate == 0, "Delayed activation cannot restart after cancellation \(action)")
            try await wait("replacement item prepares") { !engine.isLoading }
        }
        engine.setActive(false)
        let calls = gate.calls
        engine.resumeFromUserAction()
        precondition(!engine.canRequestPlayback && gate.calls == calls)
        engine.stopSession()
        print("PASS: pause, modal roundtrip, background, replacement, new interruption and inactive scene cancel delayed manual recovery")
    }
}
