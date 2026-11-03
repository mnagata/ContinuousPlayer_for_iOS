import Foundation
import Observation

struct PlaybackChromePolicy {
    var paused = false
    var audioOnly = false
    var externalPlayback = false
    var pointerAwake = false
    var hovered = false
    var focused = false
    var modal = false
    var voiceOver = false
    var visible: Bool { paused || audioOnly || externalPlayback || pointerAwake || hovered || focused || modal || voiceOver }
}

/// Frequent motion updates only the clock. Observation changes at reveal/hide,
/// not at the pointer sampling rate, and the timer belongs to this player view.
@MainActor @Observable final class PlaybackChromeState {
    private(set) var pointerAwake = false
    private(set) var usesPointer = false
    var hoveredControls: Set<String> = []
    @ObservationIgnored private var lastMotion = ContinuousClock.now
    @ObservationIgnored private var timer: Task<Void, Never>?

    func pointerMoved() {
        lastMotion = .now
        if !usesPointer { usesPointer = true }
        if !pointerAwake { pointerAwake = true }
        guard timer == nil else { return }
        timer = Task { [weak self] in
            var remaining = Duration.seconds(3)
            while !Task.isCancelled {
                try? await Task.sleep(for: remaining)
                guard !Task.isCancelled, let self else { return }
                remaining = self.lastMotion.duration(to: .now)
                if remaining >= .seconds(3) {
                    self.pointerAwake = false
                    self.timer = nil
                    return
                }
                remaining = .seconds(3) - remaining
            }
        }
    }
    func directTouch() {
        stop()
        usesPointer = false
        pointerAwake = false
        hoveredControls.removeAll()
    }
    func stop() { timer?.cancel(); timer = nil }
}
