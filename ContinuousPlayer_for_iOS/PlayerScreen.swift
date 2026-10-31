import SwiftUI
import AVFoundation
import UIKit

struct PlayerScreen: View {
    let playback: PlaybackController
    let folderName: String
    let home: () -> Void
    let chooseFolder: () -> Void
    let retry: () -> Void
    var browsingFiles = false
    private var info: MediaInfo { playback.mediaInfo }
    @State private var outputSummary = ""
    @State private var sheet: DetailSheet?
    @State private var infoPresentation: PlaybackController.PresentationSnapshot?
    @State private var commands = 0
    @State private var focusRevision = 0
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    private enum DetailSheet: String, Identifiable {
        case info
        var id: String { rawValue }
    }

    private var controlsVisible: Bool {
        playback.showsPauseControls || playback.state.ended || playback.needsFolderSelection || playback.error != nil || voiceOver
    }
    private var failureVisible: Bool { playback.showsFailure && !browsingFiles && sheet == nil }

    var body: some View {
        GeometryReader { geometry in
            let portrait = geometry.size.height > geometry.size.width
            VStack(spacing: 0) {
                ZStack {
                    PlaybackSurface(player: playback.player, enabled: acceptsInput, focusRevision: focusRevision,
                                    playing: playback.state.wantsToPlay, canSeek: playback.canSeek,
                                    onCommand: perform)
                    if ["mp3", "flac", "m4a", "aac", "wav", "ogg", "opus"].contains(playback.state.currentURL?.pathExtension.lowercased() ?? "") {
                        Image(systemName: "waveform").font(.system(size: 72)).foregroundStyle(.cyan.opacity(0.65)).accessibilityHidden(true).allowsHitTesting(false)
                    }
                    if playback.isLoading || playback.isBuffering {
                        ProgressView(playback.isLoading ? "再生準備中" : "バッファリング中")
                            .padding().background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                #if !targetEnvironment(macCatalyst)
                if portrait {
                    // Reserve the same information area in both playback states.
                    informationPanel(portrait: true)
                        .frame(height: geometry.size.height * 0.35)
                }
                #endif
            }
            #if !targetEnvironment(macCatalyst)
            .overlay(alignment: .top) {
                if controlsVisible { toolbar.background(.black.opacity(0.85)) }
            }
            #endif
            .overlay(alignment: .bottom) {
                #if targetEnvironment(macCatalyst)
                if playback.state.ended || playback.error != nil || playback.pauseReason != nil {
                    VStack(alignment: .leading, spacing: 8) {
                        playbackStatusMessages
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    .padding()
                    .background(.black.opacity(0.85))
                }
                #else
                if controlsVisible && !portrait {
                    informationPanel(portrait: false)
                        .frame(maxHeight: 110)
                        .background(.black.opacity(0.85))
                }
                #endif
            }
        }
        .allowsHitTesting(!failureVisible)
        .accessibilityHidden(failureVisible)
        .overlay {
            if failureVisible { PlaybackFailurePanel(playback: playback, retry: retry, browse: chooseFolder) }
        }
        .background(.black).foregroundStyle(.white).preferredColorScheme(.dark)
        #if DEBUG
        .overlay(alignment: .bottomLeading) { PlaybackSessionStatus(playback: playback) }
        .overlay(alignment: .bottomTrailing) {
            if ProcessInfo.processInfo.arguments.contains("--ui-session-state") {
                Text(verbatim: "commands=\(commands)")
                    .font(.caption2).accessibilityIdentifier("player.inputState").allowsHitTesting(false)
            }
        }
        #endif
        #if targetEnvironment(macCatalyst)
        .background {
            CatalystPlaybackTitlebar(filename: playback.currentName,
                                     isPlaying: playback.state.wantsToPlay,
                                     actionsEnabled: isEnabled && !browsingFiles && sheet == nil && !playback.showsFailure,
                                     playbackEnabled: playback.canResume,
                                     home: home, chooseFolder: chooseFolder,
                                     showInfo: openInfo, togglePlayback: toggle)
                .allowsHitTesting(false)
        }
        #endif
        // Keep system chrome constant so safe-area changes cannot shift the video.
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .sheet(item: $sheet, onDismiss: closeInfo) { _ in MediaInfoSheet(info: info, folderName: folderName) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active
        }
        .background {
            PlaybackMediaCommands(player: playback.player, name: playback.currentName,
                                  enabled: acceptsInput, onCommand: perform)
                .frame(width: 0, height: 0)
        }
        .onAppear(perform: refreshOutput)
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in refreshOutput() }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }

    @ViewBuilder
    private var playbackStatusMessages: some View {
        if playback.state.ended { Label("最後まで再生しました", systemImage: "checkmark.circle") }
        if let reason = playback.pauseReason { Text(reason).foregroundStyle(.secondary) }
    }

    private func informationPanel(portrait: Bool) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                playbackStatusMessages
                if portrait {
                    Text(playback.currentName).font(.headline).textSelection(.enabled)
                    Text("\(info.size)\n\(info.video)\n\(info.audio)").font(.caption).foregroundStyle(.secondary)
                    Text(outputSummary).font(.caption).foregroundStyle(.secondary)
                }
                if controlsVisible { transport }
                if controlsVisible {
                    Text("キーボード: ← 前のファイル · → 次のファイル · Space 一時停止／再生\n↑／↓ −10秒／＋10秒 · Shift＋←／→ ±10秒 · I メディア情報")
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
                control("メディア情報", "info.circle", action: openInfo)
                control(playback.state.wantsToPlay ? "一時停止" : "再生", playback.state.wantsToPlay ? "pause.fill" : "play.fill", action: toggle)
                    .disabled(!playback.canResume)
            }.padding(.horizontal, 8)
        }
        .padding(.top, 8).background(.white.opacity(0.08))
    }

    private var transport: some View {
        HStack {
            control("前のファイル", "backward.end.fill") { playback.move(-1) }.disabled(!playback.state.canGoBack || playback.needsFolderSelection)
            Spacer(minLength: 0)
            control("10秒戻す", "gobackward.10") { playback.seek(by: -10) }.disabled(!playback.canSeek)
            Spacer(minLength: 0)
            control(playback.state.wantsToPlay ? "一時停止" : "再生", playback.state.wantsToPlay ? "pause.fill" : "play.fill", action: toggle).disabled(!playback.canResume)
            Spacer(minLength: 0)
            control("10秒進める", "goforward.10") { playback.seek(by: 10) }.disabled(!playback.canSeek)
            Spacer(minLength: 0)
            control("次のファイル", "forward.end.fill") { playback.move(1) }.disabled(!playback.state.canGoForward || playback.needsFolderSelection)
        }
    }

    private func control(_ label: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        PlayerControl(label: label, symbol: symbol, action: action)
    }

    private var acceptsInput: Bool {
        isEnabled && !browsingFiles && sheet == nil && !playback.showsFailure && scenePhase == .active
    }
    private func perform(_ command: PlaybackInputCommand) {
        guard acceptsInput else { return }
        #if DEBUG
        commands += 1
        #endif
        PlaybackInputActions(playback: playback, retry: retry, browse: chooseFolder,
                             info: openInfo, home: home).perform(command)
    }

    private func openInfo() {
        guard sheet == nil else { return }
        infoPresentation = playback.beginPresentation()
        sheet = .info
    }

    private func closeInfo() {
        if let infoPresentation { playback.endPresentation(infoPresentation) }
        infoPresentation = nil
        focusRevision += 1
    }

    private func toggle() {
        perform(.toggle)
    }

    private func refreshOutput() {
        let audio = AVAudioSession.sharedInstance()
        outputSummary = "出力: \(audio.currentRoute.outputs.map(\.portName).joined(separator: ", ")) · \(String(format: "%.1f", audio.sampleRate / 1000)) kHz"
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
        .buttonStyle(.borderless).keyboardAction(action).accessibilityLabel(label)
    }
}

#Preview("情報") {
    MediaInfoSheet(info: MediaInfo(name: "星の旅 OP.mp4", size: "120 MB", video: "avc1 · 1920 × 1080 · 23.98 fps", audio: "aac · 48.0 kHz · 2 ch"), folderName: "OP・ED")
}
