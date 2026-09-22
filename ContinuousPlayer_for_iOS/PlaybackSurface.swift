import SwiftUI
import AVFoundation
import UIKit

/// 操作はPlaybackControllerを経由し、再生意図とAVPlayerを同期させる。
struct PlaybackSurface: UIViewControllerRepresentable {
    let player: AVPlayer
    var onFirstAppearance: (() -> Void)? = nil
    var keyboardEnabled = false
    var onPrevious: (() -> Void)? = nil
    var onNext: (() -> Void)? = nil
    var onTogglePlayback: (() -> Void)? = nil
    var onSeekBackward: (() -> Void)? = nil
    var onSeekForward: (() -> Void)? = nil
    var onShowInfo: (() -> Void)? = nil
    var onVolumeUp: (() -> Void)? = nil
    var onVolumeDown: (() -> Void)? = nil

    final class SurfaceView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }

    final class SurfaceController: UIViewController {
        var onFirstAppearance: (() -> Void)?
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?
        var onSeekBackward: (() -> Void)?
        var onSeekForward: (() -> Void)?
        var onVolumeUp: (() -> Void)?
        var onVolumeDown: (() -> Void)?
        var onShowInfo: (() -> Void)?
        var onTogglePlayback: (() -> Void)?
        var keyboardEnabled = false {
            didSet {
                guard keyboardEnabled != oldValue else { return }
                if keyboardEnabled, viewIfLoaded?.window != nil {
                    becomeFirstResponder()
                } else if !keyboardEnabled {
                    resignFirstResponder()
                }
            }
        }
        private var appeared = false
        var surface: SurfaceView { view as! SurfaceView }

        override var canBecomeFirstResponder: Bool { keyboardEnabled }

        override var keyCommands: [UIKeyCommand]? {
            guard keyboardEnabled else { return nil }
            return [
                command(UIKeyCommand.inputLeftArrow, title: "前のファイル", action: #selector(previousFile)),
                command(UIKeyCommand.inputRightArrow, title: "次のファイル", action: #selector(nextFile)),
                command(" ", title: "一時停止／再生", action: #selector(togglePlayback)),
                command(UIKeyCommand.inputLeftArrow, modifiers: .shift, title: "10秒戻す", action: #selector(seekBackward)),
                command(UIKeyCommand.inputRightArrow, modifiers: .shift, title: "10秒進める", action: #selector(seekForward)),
                command(UIKeyCommand.inputUpArrow, title: "音量を上げる", action: #selector(volumeUp)),
                command(UIKeyCommand.inputDownArrow, title: "音量を下げる", action: #selector(volumeDown)),
                command("i", title: "メディア情報", action: #selector(showInfo))
            ]
        }

        private func command(_ input: String, modifiers: UIKeyModifierFlags = [], title: String, action: Selector) -> UIKeyCommand {
            let command = UIKeyCommand(input: input, modifierFlags: modifiers, action: action)
            command.discoverabilityTitle = title
            command.wantsPriorityOverSystemBehavior = true
            return command
        }

        @objc private func previousFile() { if keyboardEnabled { onPrevious?() } }
        @objc private func nextFile() { if keyboardEnabled { onNext?() } }
        @objc private func togglePlayback() { if keyboardEnabled { onTogglePlayback?() } }

        @objc private func seekBackward() { if keyboardEnabled { onSeekBackward?() } }
        @objc private func seekForward() { if keyboardEnabled { onSeekForward?() } }
        @objc private func volumeUp() { if keyboardEnabled { onVolumeUp?() } }
        @objc private func volumeDown() { if keyboardEnabled { onVolumeDown?() } }
        @objc private func showInfo() { if keyboardEnabled { onShowInfo?() } }

        override func loadView() {
            let surface = SurfaceView()
            surface.backgroundColor = .black
            surface.playerLayer.videoGravity = .resizeAspect
            view = surface
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            if keyboardEnabled { becomeFirstResponder() }
            // Wait for presentation to finish; dismissing an info sheet must not resume playback.
            guard !appeared else { return }
            appeared = true
            onFirstAppearance?()
        }

        override func viewWillDisappear(_ animated: Bool) {
            resignFirstResponder()
            super.viewWillDisappear(animated)
        }
    }

    func makeUIViewController(context: Context) -> SurfaceController {
        let controller = SurfaceController()
        controller.surface.playerLayer.player = player
        controller.onFirstAppearance = onFirstAppearance
        configureKeyboard(controller)
        return controller
    }

    func updateUIViewController(_ controller: SurfaceController, context: Context) {
        if controller.surface.playerLayer.player !== player {
            controller.surface.playerLayer.player = player
        }
        controller.onFirstAppearance = onFirstAppearance
        configureKeyboard(controller)
    }

    private func configureKeyboard(_ controller: SurfaceController) {
        controller.onPrevious = onPrevious
        controller.onNext = onNext
        controller.onTogglePlayback = onTogglePlayback
        controller.onSeekBackward = onSeekBackward
        controller.onSeekForward = onSeekForward
        controller.onShowInfo = onShowInfo
        controller.onVolumeUp = onVolumeUp
        controller.onVolumeDown = onVolumeDown
        controller.keyboardEnabled = keyboardEnabled
    }

    static func dismantleUIViewController(_ controller: SurfaceController, coordinator: ()) {
        controller.onFirstAppearance = nil
        controller.keyboardEnabled = false
        controller.onPrevious = nil
        controller.onNext = nil
        controller.onTogglePlayback = nil
        controller.onSeekBackward = nil
        controller.onSeekForward = nil
        controller.onShowInfo = nil
        controller.onVolumeUp = nil
        controller.onVolumeDown = nil
        controller.surface.playerLayer.player = nil
    }
}
