#if DEBUG
import SwiftUI
import AVFoundation
import CoreMedia
import UIKit

/// Opt-in UI-test observation. Not present in normal launches or Release builds.
struct PlaybackSessionStatus: View {
    let playback: PlaybackController
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--ui-session-state") {
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                VStack(alignment: .leading) {
                Text(verbatim: "\(playback.currentName)|\(playback.state.wantsToPlay ? "playing" : "paused")|\(String(format: "%.1f", playback.player.currentTime().seconds))|presenting=\(playback.isPresenting)|allowed=\(playback.allowsPlayback)|app=\(UIApplication.shared.applicationState.rawValue)")
                    .font(.caption2).foregroundStyle(.white)
                    .accessibilityIdentifier("player.sessionState")
                    if ProcessInfo.processInfo.arguments.contains("--ui-audio-interruption-test") {
                        Button("TEST: 音声割り込みを開始") { playback.setInterrupted(true) }
                            .accessibilityIdentifier("test.audioInterruption")
                            .padding(8).background(.black)
                    }
                }
                .padding(.bottom, ProcessInfo.processInfo.arguments.contains("--ui-audio-interruption-test") ? 100 : 0)
            }
            .allowsHitTesting(ProcessInfo.processInfo.arguments.contains("--ui-audio-interruption-test"))
        }
    }
}
#endif
