import Foundation
import Observation

/// A scene owns this object; browsing views only borrow its playback engine.
@MainActor @Observable
final class PlaybackSessionCoordinator {
    let playback = PlaybackController()
    private var blockers: Set<String> = []
    private var sceneAllowsPlayback = true

    func setSceneAllowsPlayback(_ allowed: Bool) {
        sceneAllowsPlayback = allowed
        updateActivity()
    }

    func setBlocked(_ reason: String, _ blocked: Bool) {
        if blocked { blockers.insert(reason) } else { blockers.remove(reason) }
        updateActivity()
    }

    func end() { playback.stopSession() }

    private func updateActivity() {
        playback.setActive(sceneAllowsPlayback && blockers.isEmpty)
    }
}
