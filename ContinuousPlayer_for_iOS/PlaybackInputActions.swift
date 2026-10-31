import SwiftUI

@MainActor struct PlaybackInputActions {
    let playback: PlaybackController
    let retry: () -> Void
    let browse: () -> Void
    let info: () -> Void
    let home: () -> Void
    func perform(_ command: PlaybackInputCommand) {
        switch command {
        case .previous: playback.move(-1)
        case .next: playback.move(1)
        case .backward: playback.seek(by: -10)
        case .forward: playback.seek(by: 10)
        case .toggle:
            if playback.state.wantsToPlay { playback.pause() } else { play() }
        case .play: if !playback.state.wantsToPlay { play() }
        case .pause: playback.pause()
        case .browse: browse()
        case .info: info()
        case .home: home()
        }
    }
    private func play() { if playback.failure != nil { retry() } else { playback.resume() } }
}

extension KeyPress {
    var inputName: String {
        switch key {
        case .leftArrow: "left"
        case .rightArrow: "right"
        case .upArrow: "up"
        case .downArrow: "down"
        case .return: "return"
        case .escape: "escape"
        case .delete: "backspace"
        case .pageUp: "pageUp"
        case .pageDown: "pageDown"
        default: characters.lowercased()
        }
    }
    var hasCommandModifiers: Bool { !modifiers.intersection([.command, .control, .option]).isEmpty }
}

extension View {
    /// Expose app controls to Tab without changing the user's OS-wide keyboard
    /// navigation setting. Only a fresh activation key invokes the action.
    @ViewBuilder func keyboardAction(_ action: @escaping () -> Void) -> some View {
        #if os(tvOS)
        self
        #else
        self.focusable(interactions: .edit)
            .onKeyPress(keys: [.return, .space], phases: [.down, .repeat]) { key in
                guard !key.hasCommandModifiers else { return .ignored }
                if key.phase == .down { action() }
                return .handled
            }
        #endif
    }
}
