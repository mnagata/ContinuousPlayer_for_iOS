import SwiftUI
import AVFoundation
import UIKit

struct TVPlayerScreen: View {
    let playback: PlaybackController
    let folderName: String
    let home: () -> Void
    let chooseFolder: () -> Void
    let retry: () -> Void
    var browsingFiles = false
    @State private var showsInfo = false
    @State private var infoPresentation: PlaybackController.PresentationSnapshot?
    @FocusState private var focus: Focus?
    @Namespace private var transportScope
    @Environment(\.resetFocus) private var resetFocus
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    private enum Focus: Hashable { case video, home, browse, info, previous, backward, play, forward, next }
    private var controlsVisible: Bool {
        !playback.state.wantsToPlay || playback.error != nil || playback.mediaInfo.isAudioOnly || voiceOver
    }

    var body: some View {
        playerContent
        .focusScope(transportScope)
        .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
        #if DEBUG
        .overlay(alignment: .topTrailing) { PlaybackSessionStatus(playback: playback) }
        #endif
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .task(id: [browsingFiles, showsInfo, playback.showsFailure, controlsVisible, playback.state.wantsToPlay, playback.canRequestPlayback]) {
            // The overlay can remove the native focus without changing the old
            // SwiftUI value. Clear it, then restore after controls are visible.
            focus = nil
            await Task.yield()
            guard !Task.isCancelled, !browsingFiles, !showsInfo, !playback.showsFailure else { return }
            focus = playback.state.wantsToPlay ? .video : (playback.canRequestPlayback ? .play : .browse)
            resetFocus(in: transportScope)
        }
        .onChange(of: scenePhase) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active
        }
        .onPlayPauseCommand { perform(.toggle) }
        .background {
            PlaybackMediaCommands(player: playback.player, name: playback.currentName,
                                  enabled: acceptsInput, onCommand: perform).frame(width: 0, height: 0)
        }
        .sheet(isPresented: $showsInfo, onDismiss: closeInfo) {
            MediaInfoSheet(info: playback.mediaInfo, folderName: folderName)
        }
        .sheet(isPresented: failurePresentation, onDismiss: {
            if !browsingFiles && !showsInfo {
                focus = playback.state.wantsToPlay ? .video : .play
                resetFocus(in: transportScope)
            }
        }) {
            PlaybackFailurePanel(playback: playback, retry: retry, browse: chooseFolder)
        }
    }
    private var failureVisible: Bool { playback.showsFailure && !browsingFiles && !showsInfo }
    private var failurePresentation: Binding<Bool> {
        Binding(get: { failureVisible }, set: { if !$0 { playback.dismissFailure() } })
    }

    private var playerContent: some View {
        ZStack {
            TVPlaybackSurface(player: playback.player)
                .ignoresSafeArea()
            if (!controlsVisible || playback.mediaInfo.isAudioOnly) && acceptsInput {
                TVRemoteInputSurface(currentName: playback.currentName, onCommand: perform)
                    .focused($focus, equals: .video)
                    .prefersDefaultFocus(playback.state.wantsToPlay, in: transportScope)
                    .onKeyPress(phases: [.down, .repeat]) { key in
                        guard acceptsInput, !key.hasCommandModifiers,
                              let command = PlaybackKeyboardInput.command(key.inputName, shift: key.modifiers.contains(.shift))
                        else { return .ignored }
                        if key.phase == .down { perform(command) }
                        return .handled
                    }
            }
            if playback.isLoading || playback.isBuffering {
                ProgressView(playback.isLoading ? "再生準備中" : "バッファリング中")
                    .padding(30).background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 18))
                    .allowsHitTesting(false)
            }
            if playback.mediaInfo.isAudioOnly {
                Image(systemName: "waveform").font(.system(size: 100)).foregroundStyle(.cyan.opacity(0.65))
                    .allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .overlay(alignment: .top) {
            if controlsVisible && !browsingFiles && !showsInfo { topBar }
        }
        .overlay(alignment: .bottom) {
            if controlsVisible && !browsingFiles && !showsInfo { transport }
        }
    }

    private var topBar: some View {
        HStack(spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(MediaDisplayName.title(playback.currentName)).font(.title2.bold()).lineLimit(1).truncationMode(.tail)
                    .help(playback.currentName).accessibilityLabel(playback.currentName).accessibilityIdentifier("player.title")
                if playback.state.ended { Text("このフォルダーの再生が終了しました。").font(.callout).lineLimit(1) }
                else if playback.isRequestingAudioRecovery { Text("音声出力を再開しています…").font(.callout).lineLimit(1) }
                else if let reason = playback.pauseReason { Text(reason).font(.callout).lineLimit(1).truncationMode(.tail) }
            }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(-1)
            Button("ホームに戻る", systemImage: "house") { playback.pause(); home() }
                .focused($focus, equals: .home).help("ホームに戻る")
            Button("ファイル一覧", systemImage: "folder", action: leavePlayer)
                .focused($focus, equals: .browse).accessibilityIdentifier("player.chooseFolder").help("ファイル一覧")
            Button("メディア情報", systemImage: "info.circle", action: openInfo)
                .focused($focus, equals: .info).help("メディア情報")
        }
        .onMoveCommand(perform: moveControlFocus)
        .labelStyle(.iconOnly).padding(.horizontal, 64).padding(.vertical, 24)
        .background { Color.black.opacity(0.85).ignoresSafeArea(edges: [.top, .horizontal]) }

    }

    private var transport: some View {
        HStack(spacing: 36) {
            Button("前のファイル", systemImage: "backward.end.fill") { perform(.previous) }
                .focused($focus, equals: .previous).disabled(!playback.state.canGoBack || playback.needsFolderSelection)
                .opacity(playback.state.canGoBack && !playback.needsFolderSelection ? 1 : 0.3).help("前のファイル")
            Button("10秒戻す", systemImage: "gobackward.10") { perform(.backward) }
                .focused($focus, equals: .backward).disabled(!playback.canSeek).opacity(playback.canSeek ? 1 : 0.3).help("10秒戻す")
            Button(playback.state.wantsToPlay ? "一時停止" : "再生",
                   systemImage: playback.state.wantsToPlay ? "pause.fill" : "play.fill", action: toggle)
                .focused($focus, equals: .play)
                .prefersDefaultFocus(!playback.state.wantsToPlay, in: transportScope)
                .disabled(!playback.canRequestPlayback).opacity(playback.canRequestPlayback ? 1 : 0.3).accessibilityIdentifier("player.toggle")
            Button("10秒進める", systemImage: "goforward.10") { perform(.forward) }
                .focused($focus, equals: .forward).disabled(!playback.canSeek).opacity(playback.canSeek ? 1 : 0.3).help("10秒進める")
            Button("次のファイル", systemImage: "forward.end.fill") { perform(.next) }
                .focused($focus, equals: .next).disabled(!playback.state.canGoForward || playback.needsFolderSelection)
                .opacity(playback.state.canGoForward && !playback.needsFolderSelection ? 1 : 0.3).help("次のファイル")
        }
        .onMoveCommand(perform: moveControlFocus)
        .labelStyle(.iconOnly).padding(.vertical, 28).frame(maxWidth: .infinity)
        .background { Color.black.opacity(0.85).ignoresSafeArea(edges: [.bottom, .horizontal]) }

    }


    private func moveControlFocus(_ direction: MoveCommandDirection) {
        let top: [Focus] = [.home, .browse, .info]
        var bottom: [Focus] = []
        if playback.state.canGoBack && !playback.needsFolderSelection { bottom.append(.previous) }
        if playback.canSeek { bottom.append(.backward) }
        if playback.canRequestPlayback { bottom.append(.play) }
        if playback.canSeek { bottom.append(.forward) }
        if playback.state.canGoForward && !playback.needsFolderSelection { bottom.append(.next) }
        guard let current = focus else { return }
        switch direction {
        case .up where bottom.contains(current):
            switch current {
            case .previous, .backward: focus = .home
            case .forward, .next: focus = .info
            default: focus = .browse
            }
        case .down where top.contains(current): focus = bottom.contains(.play) ? .play : bottom.first
        case .left, .right:
            let row = top.contains(current) ? top : bottom
            guard let index = row.firstIndex(of: current) else { return }
            let next = index + (direction == .left ? -1 : 1)
            if row.indices.contains(next) { focus = row[next] }
        default: break
        }
    }

    private func openInfo() {
        guard !showsInfo else { return }
        infoPresentation = playback.beginPresentation()
        showsInfo = true
    }

    private func closeInfo() {
        if let infoPresentation { playback.endPresentation(infoPresentation) }
        infoPresentation = nil
    }

    private var acceptsInput: Bool { isEnabled && !browsingFiles && !showsInfo && !playback.showsFailure && scenePhase == .active }
    private func perform(_ command: PlaybackInputCommand) {
        guard acceptsInput else { return }
        PlaybackInputActions(playback: playback, retry: retry, browse: chooseFolder,
                             info: openInfo, home: home).perform(command)
    }
    private func toggle() { perform(.toggle) }

    private func leavePlayer() {
        chooseFolder()
    }

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

/// Directional presses and indirect touch each have one native owner. No
/// onMoveCommand is installed on the video, so focus-generated moves cannot
/// replay the swipe. A press during that contact also suppresses its final swipe.
private struct TVRemoteInputSurface: UIViewRepresentable {
    let currentName: String
    let onCommand: (PlaybackInputCommand) -> Void
    final class InputView: UIView {
        var onCommand: ((PlaybackInputCommand) -> Void)?
        var input = TVDirectionalInput()
        override var canBecomeFocused: Bool { true }
        override var canBecomeFirstResponder: Bool { isFocused }
        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityIdentifier = "player.video"
            accessibilityLabel = "再生領域。決定で一時停止、左右で前後、上下で10秒移動"
            let touch = RemoteTouch(target: self, action: #selector(swiped(_:)))
            touch.owner = self
            touch.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
            touch.allowedPressTypes = []
            addGestureRecognizer(touch)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)
            if isFocused { becomeFirstResponder() } else { resignFirstResponder(); input.reset() }
        }
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var unhandled = presses
            for press in presses where press.key == nil {
                let command: PlaybackInputCommand?
                switch press.type {
                case .leftArrow: command = .previous
                case .rightArrow: command = .next
                case .upArrow: command = .backward
                case .downArrow: command = .forward
                case .select: command = .toggle
                default: command = nil
                }
                if let command {
                    unhandled.remove(press)
                    if let result = input.press(ObjectIdentifier(press).hashValue, command: command) { onCommand?(result) }
                }
            }
            if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
        }
        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            presses.forEach { input.release(ObjectIdentifier($0).hashValue) }
            super.pressesEnded(presses, with: event)
        }
        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            presses.forEach { input.release(ObjectIdentifier($0).hashValue) }
            super.pressesCancelled(presses, with: event)
        }
        @objc private func swiped(_ gesture: RemoteTouch) {
            if let command = gesture.command { onCommand?(command) }
        }
    }
    final class RemoteTouch: UIGestureRecognizer {
        weak var owner: InputView?
        var start: CGPoint?
        var command: PlaybackInputCommand?
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            guard start == nil, touches.count == 1, let touch = touches.first else { state = .failed; return }
            start = touch.location(in: view); owner?.input.touchBegan()
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
            guard let start, let point = touches.first?.location(in: view) else { state = .failed; return }
            let dx = point.x - start.x, dy = point.y - start.y
            let direction: PlaybackInputCommand? = max(abs(dx), abs(dy)) < 12 ? nil
                : abs(dx) > abs(dy) ? (dx < 0 ? .previous : .next) : (dy < 0 ? .backward : .forward)
            command = owner?.input.touchEnded(command: direction)
            state = command == nil ? .failed : .recognized
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { _ = owner?.input.touchEnded(command: nil); state = .cancelled }
        override func reset() { super.reset(); start = nil; command = nil }
    }
    func makeUIView(context: Context) -> InputView { InputView() }
    func updateUIView(_ view: InputView, context: Context) { view.onCommand = onCommand; view.accessibilityValue = currentName }
    static func dismantleUIView(_ view: InputView, coordinator: ()) { view.onCommand = nil; view.input.reset() }
}
