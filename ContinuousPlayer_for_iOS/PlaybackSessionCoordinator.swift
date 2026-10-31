import Foundation
import Observation
import OSLog

/// A scene owns this object; browsing views only borrow its playback engine.
@MainActor @Observable
final class PlaybackSessionCoordinator {
    let playback = PlaybackController()
    private var blockers: Set<String> = []
    private var sceneAllowsPlayback = true
    private let logger = Logger(subsystem: "jp.nagu.ContinuousPlayer-for-iOS", category: "PlaybackLifecycle")

    func setSceneAllowsPlayback(_ allowed: Bool) {
        guard sceneAllowsPlayback != allowed else { return }
        logger.notice("Scene playback allowed=\(allowed)")
        sceneAllowsPlayback = allowed
        updateActivity()
    }

    func setBlocked(_ reason: String, _ blocked: Bool) {
        guard blockers.contains(reason) != blocked else { return }
        logger.notice("Playback blocker \(reason, privacy: .public)=\(blocked)")
        if blocked { blockers.insert(reason) } else { blockers.remove(reason) }
        updateActivity()
    }

    func end() { playback.stopSession() }

    private func updateActivity() {
        playback.setActive(sceneAllowsPlayback && blockers.isEmpty)
    }
}
