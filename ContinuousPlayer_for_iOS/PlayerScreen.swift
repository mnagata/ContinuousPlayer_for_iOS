import SwiftUI
import AVFoundation
import UIKit

struct PlayerScreen: View {
    let playback: PlaybackController
    let folderName: String
    let home: () -> Void
    let chooseFolder: () -> Void
    private var info: MediaInfo { playback.mediaInfo }
    @State private var outputSummary = ""
    @State private var sheet: DetailSheet?
    @State private var volumeFeedbackID = 0
    @State private var showsVolume = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    private enum DetailSheet: String, Identifiable {
        case info
        var id: String { rawValue }
    }

    private var controlsVisible: Bool {
        playback.showsPauseControls || playback.state.ended || playback.needsFolderSelection || playback.error != nil || voiceOver
    }

    var body: some View {
        GeometryReader { geometry in
            let portrait = geometry.size.height > geometry.size.width
            VStack(spacing: 0) {
                ZStack {
                    PlaybackSurface(
                        player: playback.player,
                        onFirstAppearance: { playback.resume() },
                        keyboardEnabled: sheet == nil && scenePhase == .active && !playback.needsFolderSelection,
                        onPrevious: { playback.move(-1) },
                        onNext: { playback.move(1) },
                        onTogglePlayback: toggle,
                        onSeekBackward: { playback.seek(by: -10) },
                        onSeekForward: { playback.seek(by: 10) },
                        onShowInfo: { sheet = .info },
                        onVolumeUp: { adjustVolume(by: 5) },
                        onVolumeDown: { adjustVolume(by: -5) }
                    )
                    if ["mp3", "flac", "m4a", "aac", "wav", "ogg", "opus"].contains(playback.state.currentURL?.pathExtension.lowercased() ?? "") {
                        Image(systemName: "waveform").font(.system(size: 72)).foregroundStyle(.cyan.opacity(0.65)).accessibilityHidden(true)
                    }
                    touchControls
                    if showsVolume {
                        Label("再生音量 \(playback.volumePercent)%", systemImage: playback.volumePercent == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.headline.monospacedDigit())
                            .padding().background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                            .allowsHitTesting(false)
                    }
                    if playback.isLoading || playback.isBuffering {
                        ProgressView(playback.isLoading ? "再生準備中" : "バッファリング中")
                            .padding().background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if portrait {
                    // Reserve the same information area in both playback states.
                    informationPanel(portrait: true)
                        .frame(height: geometry.size.height * 0.35)
                }
            }
            .overlay(alignment: .top) {
                if controlsVisible { toolbar.background(.black.opacity(0.85)) }
            }
            .overlay(alignment: .bottom) {
                if controlsVisible && !portrait {
                    informationPanel(portrait: false)
                        .frame(maxHeight: 110)
                        .background(.black.opacity(0.85))
                }
            }
        }
        .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
        // Keep system chrome constant so safe-area changes cannot shift the video.
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(item: $sheet) { _ in MediaInfoSheet(info: info, folderName: folderName) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active
        }
        .task(id: volumeFeedbackID) {
            guard showsVolume else { return }
            do { try await Task.sleep(for: .seconds(1.5)) } catch { return }
            showsVolume = false
        }
        .onAppear(perform: refreshOutput)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in refreshOutput() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    private func informationPanel(portrait: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if playback.state.ended { Label("最後まで再生しました", systemImage: "checkmark.circle") }
                if let error = playback.error { Text(error).foregroundStyle(.orange) }
                if let reason = playback.pauseReason { Text(reason).foregroundStyle(.secondary) }
                if portrait {
                    Text(playback.currentName).font(.headline).textSelection(.enabled)
                    Text("\(info.size)\n\(info.video)\n\(info.audio)").font(.caption).foregroundStyle(.secondary)
                    Text(outputSummary).font(.caption).foregroundStyle(.secondary)
                }
                if controlsVisible { transport }
                if controlsVisible {
                    Text("キーボード: ← 前のファイル · → 次のファイル · Space 一時停止／再生\nShift＋←／→ ±10秒 · ↑／↓ 音量 · I メディア情報")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                if portrait && !controlsVisible {
                    Text("左右タップで±10秒 · 中央タップで一時停止\n左右スワイプで前後のファイル")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: 760, alignment: .leading).padding()
        }
    }

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(playback.currentName).font(.subheadline).lineLimit(1).truncationMode(.middle).padding(.horizontal)
            HStack {
                control("ホームに戻る", "house", action: home)
                Spacer()
                control("OP / EDを選び直す", "folder", action: chooseFolder)
                control("メディア情報", "info.circle") { sheet = .info }
                control(playback.state.wantsToPlay ? "一時停止" : "再生", playback.state.wantsToPlay ? "pause.fill" : "play.fill", action: toggle)
                    .disabled(playback.needsFolderSelection)
            }.padding(.horizontal, 8)
        }
        .padding(.top, 8).background(.white.opacity(0.08))
    }

    private var touchControls: some View {
        HStack(spacing: 0) {
            touchRegion("10秒戻す") { playback.seek(by: -10) }
            touchRegion(playback.state.wantsToPlay ? "一時停止" : "再生", action: toggle)
            touchRegion("10秒進める") { playback.seek(by: 10) }
        }
        .highPriorityGesture(DragGesture(minimumDistance: 35).onEnded { value in
            guard abs(value.translation.width) > 70,
                  abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            playback.move(value.translation.width < 0 ? 1 : -1)
        })
    }

    private func touchRegion(_ label: String, action: @escaping () -> Void) -> some View {
        Color.clear.contentShape(Rectangle())
            .onTapGesture(count: 2, perform: action)
            .onTapGesture(perform: action)
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { action() }
    }

    private var transport: some View {
        HStack {
            control("前のファイル", "backward.end.fill") { playback.move(-1) }.disabled(!playback.state.canGoBack || playback.needsFolderSelection)
            Spacer(minLength: 0)
            control("10秒戻す", "gobackward.10") { playback.seek(by: -10) }
            Spacer(minLength: 0)
            control(playback.state.wantsToPlay ? "一時停止" : "再生", playback.state.wantsToPlay ? "pause.fill" : "play.fill", action: toggle).disabled(playback.needsFolderSelection)
            Spacer(minLength: 0)
            control("10秒進める", "goforward.10") { playback.seek(by: 10) }
            Spacer(minLength: 0)
            control("次のファイル", "forward.end.fill") { playback.move(1) }.disabled(!playback.state.canGoForward || playback.needsFolderSelection)
        }
    }

    private func control(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        PlayerControl(label: label, symbol: symbol, action: action)
    }

    private func adjustVolume(by percentagePoints: Int) {
        playback.adjustVolume(by: percentagePoints)
        showsVolume = true
        volumeFeedbackID += 1
    }

    private func toggle() {
        if playback.state.wantsToPlay { playback.pause() } else { playback.resume() }
    }

    private func refreshOutput() {
        let audio = AVAudioSession.sharedInstance()
        outputSummary = "出力: \(audio.currentRoute.outputs.map(\.portName).joined(separator: ", ")) · \(String(format: "%.1f", audio.sampleRate / 1000)) kHz"
    }
}

private struct MediaInfoSheet: View {
    let info: MediaInfo
    let folderName: String
    @Environment(\.dismiss) private var dismiss
    @State private var route = ""
    @State private var sampleRate = ""
    var body: some View {
        NavigationStack {
            List {
                Section("ファイル") {
                    LabeledContent("名前", value: info.name)
                    LabeledContent("フォルダー", value: folderName)
                    LabeledContent("サイズ", value: info.size)
                }
                Section("メディア形式") {
                    LabeledContent("映像", value: info.video)
                    LabeledContent("音声", value: info.audio)
                }
                Section("音声出力") {
                    LabeledContent("デバイス", value: route)
                    LabeledContent("実際の出力設定", value: sampleRate)
                    Text("出力設定はAVAudioSessionの現在値です。ビットパーフェクトを保証するものではありません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .textSelection(.enabled)
            .safeAreaInset(edge: .bottom) {
                Text("キーボード: I または Esc で閉じる")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
            }
            .background(InfoKeyboardCommands { dismiss() })
            .navigationTitle("メディア情報").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("閉じる") { dismiss() } } }
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in refresh() }
    }
    private func refresh() {
        let audio = AVAudioSession.sharedInstance()
        route = audio.currentRoute.outputs.map(\.portName).joined(separator: ", ")
        sampleRate = "\(String(format: "%.1f", audio.sampleRate / 1000)) kHz · \(audio.outputNumberOfChannels) ch"
    }
}

private struct PlayerControl: View {
    let label: String
    let symbol: String
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.title3)
                .frame(minWidth: 44, minHeight: 44)
                .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(.borderless).accessibilityLabel(label)
    }
}

#Preview("情報") {
    MediaInfoSheet(info: MediaInfo(name: "星の旅 OP.mp4", size: "120 MB", video: "avc1 · 1920 × 1080 · 23.98 fps", audio: "aac · 48.0 kHz · 2 ch"), folderName: "OP・ED")
}

/// Own the responder in the sheet so playback shortcuts cannot leak through it.
private struct InfoKeyboardCommands: UIViewControllerRepresentable {
    let close: () -> Void

    final class Controller: UIViewController {
        var close: (() -> Void)?
        override var canBecomeFirstResponder: Bool { true }
        override var keyCommands: [UIKeyCommand]? {
            ["i", UIKeyCommand.inputEscape].map { input in
                let command = UIKeyCommand(input: input, modifierFlags: [], action: #selector(closeInfo))
                command.discoverabilityTitle = "メディア情報を閉じる"
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }
        override func viewWillDisappear(_ animated: Bool) {
            resignFirstResponder()
            super.viewWillDisappear(animated)
        }
        @objc private func closeInfo() { close?() }
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.view.isUserInteractionEnabled = false
        controller.close = close
        return controller
    }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.close = close
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.resignFirstResponder()
        controller.close = nil
    }
}
