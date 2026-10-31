import SwiftUI
import AVFoundation
import MediaPlayer

/// Per-player command centers avoid a global handler shared by unrelated windows.
struct PlaybackMediaCommands: UIViewRepresentable {
    let player: AVPlayer
    let name: String
    let enabled: Bool
    let onCommand: (PlaybackInputCommand) -> Void

    final class Receiver: UIView {
        var session: MPNowPlayingSession?
        var targets: [(MPRemoteCommand, Any)] = []
        var enabled = false
        var onCommand: ((PlaybackInputCommand) -> Void)?
        func configure(player: AVPlayer) {
            if session?.players.first === player { return }
            stop()
            let session = MPNowPlayingSession(players: [player])
            self.session = session
            let center = session.remoteCommandCenter
            var commands: [(MPRemoteCommand, PlaybackInputCommand)] = [
                (center.playCommand, .play), (center.pauseCommand, .pause),
                (center.nextTrackCommand, .next), (center.previousTrackCommand, .previous),
                (center.skipForwardCommand, .forward), (center.skipBackwardCommand, .backward),
                (center.seekForwardCommand, .forward), (center.seekBackwardCommand, .backward)]
            #if !os(tvOS)
            commands.append((center.togglePlayPauseCommand, .toggle))
            #endif
            // tvOS Play/Pause is owned by the scene's native onPlayPauseCommand.
            center.skipForwardCommand.preferredIntervals = [10]
            center.skipBackwardCommand.preferredIntervals = [10]
            for (command, action) in commands {
                let target = command.addTarget { [weak self] event in
                    if let seek = event as? MPSeekCommandEvent, seek.type != .beginSeeking { return .success }
                    Task { @MainActor [weak self] in
                        guard let self, self.enabled, self.window?.isKeyWindow == true,
                              self.window?.rootViewController?.presentedViewController == nil else { return }
                        self.onCommand?(action)
                    }
                    return .success
                }
                targets.append((command, target))
            }
        }
        func activateIfPossible() {
            targets.forEach { $0.0.isEnabled = enabled }
            if enabled, window?.isKeyWindow == true, let session, !session.isActive, session.canBecomeActive {
                session.becomeActiveIfPossible(completion: nil)
            }
        }
        override func didMoveToWindow() { super.didMoveToWindow(); activateIfPossible() }
        func stop() {
            targets.forEach { $0.0.removeTarget($0.1) }
            targets = []; session?.nowPlayingInfoCenter.nowPlayingInfo = nil; session = nil
        }
        isolated deinit { stop() }
    }
    func makeUIView(context: Context) -> Receiver { Receiver() }
    func updateUIView(_ view: Receiver, context: Context) {
        view.configure(player: player)
        view.enabled = enabled; view.onCommand = onCommand
        let time = player.currentTime().seconds
        view.session?.nowPlayingInfoCenter.nowPlayingInfo = [
            MPMediaItemPropertyTitle: name,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: time.isFinite ? time : 0,
            MPNowPlayingInfoPropertyPlaybackRate: player.rate]
        view.activateIfPossible()
    }
    static func dismantleUIView(_ view: Receiver, coordinator: ()) { view.onCommand = nil; view.stop() }
}
