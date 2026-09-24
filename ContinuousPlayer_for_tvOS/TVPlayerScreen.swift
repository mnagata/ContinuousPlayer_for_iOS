import SwiftUI
import AVFoundation
import UIKit

struct TVPlayerScreen: View {
    let playback: PlaybackController
    let folderName: String
    let home: () -> Void
    let chooseFolder: () -> Void
    @State private var showsControls = false
    @State private var showsInfo = false
    @State private var startedPlayback = false
    @FocusState private var focus: Focus?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    private enum Focus: Hashable { case video, play }
    private var controlsVisible: Bool {
        showsControls || !playback.state.wantsToPlay || playback.error != nil || voiceOver
    }

    var body: some View {
        ZStack {
            TVPlaybackSurface(player: playback.player)
                .ignoresSafeArea()
            if !controlsVisible {
                TVRemoteInputSurface(currentName: playback.currentName,
                                     onPrevious: { playback.move(-1) },
                                     onNext: { playback.move(1) },
                                     onShowControls: { showsControls = true })
                    .focused($focus, equals: .video)
                    .onMoveCommand { direction in
                        switch direction {
                        // Move commands also include edge taps; only touch swipes change files.
                        case .left, .right: break
                        default: showsControls = true
                        }
                    }
            }
            if playback.isLoading || playback.isBuffering {
                ProgressView(playback.isLoading ? "再生準備中" : "バッファリング中")
                    .padding(30).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                    .allowsHitTesting(false)
            }
            if controlsVisible {
                VStack(alignment: .leading, spacing: 24) {
                    Text(playback.currentName).font(.title2.bold()).lineLimit(2)
                    Text(folderName).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let error = playback.error {
                        Text(error).foregroundStyle(.orange).font(.callout).lineLimit(3)
                    } else if playback.state.ended {
                        Text("このフォルダーの再生が終了しました。")
                    } else if let reason = playback.pauseReason {
                        Text(reason).font(.callout)
                    }
                    HStack(spacing: 30) {
                        Button("前の動画", systemImage: "backward.end.fill") { playback.move(-1) }
                            .disabled(!playback.state.canGoBack)
                        Button("10秒戻す", systemImage: "gobackward.10") { playback.seek(by: -10) }
                        Button(playback.state.wantsToPlay ? "一時停止" : "再生",
                               systemImage: playback.state.wantsToPlay ? "pause.fill" : "play.fill", action: toggle)
                            .focused($focus, equals: .play)
                            .accessibilityIdentifier("player.toggle")
                        Button("10秒進める", systemImage: "goforward.10") { playback.seek(by: 10) }
                        Button("次の動画", systemImage: "forward.end.fill") { playback.move(1) }
                            .disabled(!playback.state.canGoForward)
                    }
                    .labelStyle(.iconOnly)
                    HStack(spacing: 30) {
                        Button("一覧に戻る", action: leavePlayer)
                            .accessibilityIdentifier("player.chooseFolder")
                        Button("メディア情報") { showsInfo = true }
                        Button("ホームに戻る") { playback.pause(); home() }
                        if playback.state.wantsToPlay && !voiceOver {
                            Button("映像に戻る") { showsControls = false }
                        }
                    }
                    Text("再生／停止ボタンで切り替え · 戻るボタンで操作表示／一覧へ")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(48)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.black.opacity(0.88))
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
        }
        .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
        .onPlayPauseCommand { if !showsInfo { toggle() } }
        .onExitCommand {
            if showsInfo { showsInfo = false }
            else if controlsVisible { leavePlayer() }
            else { showsControls = true }
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            // Returning from a presented detail view must not resume a paused item.
            if !startedPlayback {
                startedPlayback = true
                playback.resume()
            }
            updateFocus()
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            playback.pause()
        }
        .onChange(of: controlsVisible) { _, _ in updateFocus() }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active
        }
        .sheet(isPresented: $showsInfo, onDismiss: { updateFocus() }) {
            VStack(alignment: .leading, spacing: 28) {
                Text("メディア情報").font(.title)
                Text(playback.mediaInfo.name).font(.headline).lineLimit(3)
                Text("サイズ: \(playback.mediaInfo.size)")
                Text("映像: \(playback.mediaInfo.video)")
                Text("音声: \(playback.mediaInfo.audio)")
                Button("閉じる") { showsInfo = false }
            }
            .padding(60)
            .onExitCommand { showsInfo = false }
        }
    }

    private func toggle() {
        if playback.state.wantsToPlay { playback.pause() }
        else { showsControls = false; playback.resume() }
    }

    private func leavePlayer() {
        playback.pause()
        chooseFolder()
    }

    private func updateFocus() { focus = controlsVisible ? .play : .video }
}

/// Keep transport commands in PlaybackController so end-of-file and error recovery remain shared.
private struct TVPlaybackSurface: UIViewRepresentable {
    let player: AVPlayer
    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: Surface, context: Context) { view.playerLayer.player = player }
    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.playerLayer.player = nil }
}

/// Receive actual touch movement separately from the remote's directional button presses.
private struct TVRemoteInputSurface: UIViewRepresentable {
    let currentName: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onShowControls: () -> Void

    final class InputView: UIView {
        var onPrevious: (() -> Void)?
        var onNext: (() -> Void)?
        var onShowControls: (() -> Void)?
        override var canBecomeFocused: Bool { true }

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityIdentifier = "player.video"
            accessibilityLabel = "再生中。選択で操作ボタンを表示"
            for direction: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
                swipe.direction = direction
                swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
                swipe.allowedPressTypes = []
                addGestureRecognizer(swipe)
            }
            let select = UITapGestureRecognizer(target: self, action: #selector(selected))
            select.allowedTouchTypes = []
            select.allowedPressTypes = [NSNumber(value: UIPress.PressType.select.rawValue)]
            addGestureRecognizer(select)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
            guard gesture.state == .ended else { return }
            switch gesture.direction {
            case .left: onPrevious?()
            case .right: onNext?()
            default: onShowControls?()
            }
        }

        @objc private func selected() { onShowControls?() }
    }

    func makeUIView(context: Context) -> InputView {
        let view = InputView()
        updateUIView(view, context: context)
        return view
    }

    func updateUIView(_ view: InputView, context: Context) {
        view.onPrevious = onPrevious
        view.onNext = onNext
        view.onShowControls = onShowControls
        view.accessibilityValue = currentName
    }

    static func dismantleUIView(_ view: InputView, coordinator: ()) {
        view.onPrevious = nil
        view.onNext = nil
        view.onShowControls = nil
    }
}
