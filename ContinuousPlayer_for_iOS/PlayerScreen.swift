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
    var onWindowMinimizedChange: (Bool) -> Void = { _ in }
    @State private var sheet: DetailSheet?
    @State private var infoPresentation: PlaybackController.PresentationSnapshot?
    @State private var commands = 0
    @State private var focusRevision = 0
    @State private var chrome = PlaybackChromeState()
    @State private var fullScreen = false
    @State private var nativeToolbarFocused = false
    @State private var nativeToolbarHovered = false
    @State private var navigatingControls = false
    @FocusState private var focusedControl: String?
    @State private var nativeControlFocus: String?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    private enum DetailSheet: String, Identifiable { case info; var id: String { rawValue } }

    private var controlFocus: String? {
        get {
            #if targetEnvironment(macCatalyst)
            nativeControlFocus
            #else
            focusedControl
            #endif
        }
        nonmutating set {
            #if targetEnvironment(macCatalyst)
            nativeControlFocus = newValue
            #else
            focusedControl = newValue
            #endif
        }
    }
    private var controlsVisible: Bool {
        PlaybackChromePolicy(paused: playback.showsPauseControls || playback.state.ended || playback.error != nil || playback.needsFolderSelection,
            audioOnly: playback.mediaInfo.isAudioOnly, pointerAwake: chrome.pointerAwake,
            hovered: !chrome.hoveredControls.isEmpty || nativeToolbarHovered, focused: controlFocus != nil || nativeToolbarFocused || navigatingControls,
            modal: browsingFiles || sheet != nil || playback.showsFailure, voiceOver: voiceOver).visible
    }
    private var failureVisible: Bool { playback.showsFailure && !browsingFiles && sheet == nil }
    private var cursorHidden: Bool { chrome.usesPointer && !controlsVisible && acceptsInput }
    private var status: String? {
        if playback.isRequestingAudioRecovery { return "音声出力を再開しています…" }
        if playback.state.ended { return "このフォルダーの再生が終了しました。" }
        if playback.error != nil { return "再生できません" }
        return playback.pauseReason
    }

    var body: some View {
        ZStack {
            PlaybackSurface(player: playback.player, enabled: acceptsInput, focusRevision: focusRevision,
                playing: playback.state.wantsToPlay, canSeek: playback.canSeek,
                cursorHidden: cursorHidden, onPointerActivity: chrome.pointerMoved,
                onDirectTouch: { chrome.directTouch(); navigatingControls = false; controlFocus = nil }, onTab: focusControls, onCommand: perform)
                #if targetEnvironment(macCatalyst)
                // The native titlebar belongs outside the video viewport. Fit
                // every aspect ratio below it; only full screen is edge-to-edge.
                .ignoresSafeArea(.container, edges: fullScreen ? .all : [.horizontal, .bottom])
                #else
                .ignoresSafeArea()
                #endif
            if playback.mediaInfo.isAudioOnly {
                Image(systemName: "waveform").font(.system(size: 72)).foregroundStyle(.cyan.opacity(0.65))
                    .accessibilityHidden(true).allowsHitTesting(false)
            }
            if playback.isLoading || playback.isBuffering {
                ProgressView(playback.isLoading ? "再生準備中" : "バッファリング中")
                    .padding().background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
                    .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .top) {
            #if targetEnvironment(macCatalyst)
            if controlsVisible && fullScreen { topBar }
            #else
            if controlsVisible { topBar }
            #endif
        }
        .overlay(alignment: .bottom) {
            if controlsVisible { transport.padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background { Color.black.opacity(0.85).ignoresSafeArea(edges: [.bottom, .horizontal]) } }
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
                VStack {
                Text(verbatim: "controls=\(controlsVisible)|cursorHidden=\(cursorHidden)|fullScreen=\(fullScreen)|audioOnly=\(playback.mediaInfo.isAudioOnly)|pointer=\(chrome.pointerAwake)|hover=\(chrome.hoveredControls.count)|focus=\(controlFocus ?? "nil")|nativeFocus=\(nativeToolbarFocused)|nativeHover=\(nativeToolbarHovered)")
                    .accessibilityIdentifier("player.chromeState")
                Text(verbatim: "commands=\(commands)")
                    .accessibilityIdentifier("player.inputState")
                }.font(.caption2)
                    .allowsHitTesting(false)
            }
        }
        #endif
        #if targetEnvironment(macCatalyst)
        .background {
            CatalystPlaybackTitlebar(filename: playback.currentName, status: status,
                controlsVisible: controlsVisible, fullScreen: fullScreen, cursorHidden: cursorHidden,
                actionsEnabled: isEnabled && !browsingFiles && sheet == nil && !playback.showsFailure,
                home: home, chooseFolder: chooseFolder, showInfo: openInfo,
                onPointerActivity: chrome.pointerMoved, onFullScreenChange: {
                    guard fullScreen != $0 else { return }
                    fullScreen = $0
                    navigatingControls = false; controlFocus = nil; nativeToolbarFocused = false; nativeToolbarHovered = false
                    chrome.hoveredControls.removeAll()
                },
                onToolbarFocusChange: { nativeToolbarFocused = $0 },
                onToolbarHoverChange: { nativeToolbarHovered = $0 },
                onToolbarExit: focusControls, onWindowMinimizedChange: onWindowMinimizedChange)
                .allowsHitTesting(false)
        }
        #endif
        .onContinuousHover { phase in if case .active = phase { chrome.pointerMoved() } }
        .statusBarHidden(true).persistentSystemOverlays(.hidden)
        .sheet(item: $sheet, onDismiss: closeInfo) { _ in MediaInfoSheet(info: playback.mediaInfo, folderName: folderName) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            UIApplication.shared.isIdleTimerDisabled = phase == .active
            if phase != .active { chrome.stop() }
            else if chrome.usesPointer { chrome.pointerMoved() }
        }
        .onChange(of: playback.state.wantsToPlay) { _, playing in
            if playing { navigatingControls = false; controlFocus = nil; focusRevision += 1 }
        }
        .background {
            PlaybackMediaCommands(player: playback.player, name: playback.currentName,
                enabled: acceptsInput, onCommand: perform).frame(width: 0, height: 0)
        }
        .onDisappear { chrome.stop(); UIApplication.shared.isIdleTimerDisabled = false }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(MediaDisplayName.title(playback.currentName)).font(.subheadline)
                    .lineLimit(1).truncationMode(.tail).help(playback.currentName)
                    .accessibilityLabel(playback.currentName).accessibilityIdentifier("player.title")
                if let status { Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail) }
            }.frame(maxWidth: .infinity, alignment: .leading).layoutPriority(-1)
            control("ホームに戻る", "house", id: "home", action: home)
            control("ファイル一覧", "folder", id: "browse", action: chooseFolder)
            control("メディア情報", "info.circle", id: "info", action: openInfo)
            #if targetEnvironment(macCatalyst)
            control("全画面を解除", "arrow.down.right.and.arrow.up.left", id: "fullscreen") {
                MacPlaybackWindowPolicy.makeBridge()?.togglePlaybackFullScreen()
            }
            #endif
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background { Color.black.opacity(0.85).ignoresSafeArea(edges: [.top, .horizontal]) }

    }
    private var transport: some View {
        HStack(spacing: 12) {
            control("前のファイル", "backward.end.fill", id: "previous") { perform(.previous) }
                .disabled(!playback.state.canGoBack || playback.needsFolderSelection)
            control("10秒戻す", "gobackward.10", id: "backward") { perform(.backward) }.disabled(!playback.canSeek)
            control(playback.state.wantsToPlay ? "一時停止" : "再生", playback.state.wantsToPlay ? "pause.fill" : "play.fill", id: "play") { perform(.toggle) }
                .disabled(!playback.canRequestPlayback).accessibilityIdentifier("player.toggle")
            control("10秒進める", "goforward.10", id: "forward") { perform(.forward) }.disabled(!playback.canSeek)
            control("次のファイル", "forward.end.fill", id: "next") { perform(.next) }
                .disabled(!playback.state.canGoForward || playback.needsFolderSelection)
        }
    }
    private func control(_ label: String, _ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        PlaybackControlButton(label: label, symbol: symbol, id: id, requestsFocus: controlFocus == id,
            action: action, navigate: { name, shift in
                if name == "escape" { perform(.browse) }
                else { moveControlFocus(from: id, backwards: name == "left" || name == "up" || (name == "tab" && shift), tab: name == "tab") }
            }, focusChanged: { focused in
                if focused { nativeControlFocus = id; navigatingControls = false }
                else if nativeControlFocus == id { nativeControlFocus = nil }
            })
        #if !targetEnvironment(macCatalyst)
        .focused($focusedControl, equals: id)
        .onKeyPress(keys: [.tab], phases: [.down, .repeat]) { key in
            guard !key.hasCommandModifiers else { return .ignored }
            if key.phase == .down { moveControlFocus(from: id, backwards: key.modifiers.contains(.shift)) }
            return .handled
        }
        #endif
        .onHover { hovering in
            if hovering { chrome.hoveredControls.insert(id); chrome.pointerMoved() }
            else { chrome.hoveredControls.remove(id) }
        }
        .onDisappear { chrome.hoveredControls.remove(id) }
    }

    private func focusControls(_ backwards: Bool) {
        // AppKit resigns its toolbar responder before UIKit can accept the next
        // control. Apply SwiftUI focus after that responder transition settles.
        navigatingControls = true
        Task { @MainActor in
            await Task.yield()
            #if targetEnvironment(macCatalyst)
            if !fullScreen {
                controlFocus = backwards ? (playback.state.canGoForward ? "next" : (playback.canSeek ? "forward" : "play"))
                    : (playback.state.canGoBack ? "previous" : (playback.canSeek ? "backward" : "play"))
                return
            }
            #endif
            controlFocus = backwards ? (playback.state.canGoForward ? "next" : (playback.canSeek ? "forward" : "play")) : "home"
        }
    }
    private func moveControlFocus(from id: String, backwards: Bool, tab: Bool = true) {
        var ids = ["home", "browse", "info"]
        #if targetEnvironment(macCatalyst)
        if !fullScreen { ids = [] }
        #endif
        #if targetEnvironment(macCatalyst)
        if fullScreen { ids.append("fullscreen") }
        #endif
        if playback.state.canGoBack && !playback.needsFolderSelection { ids.append("previous") }
        if playback.canSeek { ids.append("backward") }
        if playback.canRequestPlayback { ids.append("play") }
        if playback.canSeek { ids.append("forward") }
        if playback.state.canGoForward && !playback.needsFolderSelection { ids.append("next") }
        guard let index = ids.firstIndex(of: id) else { return }
        let next = index + (backwards ? -1 : 1)
        if ids.indices.contains(next) { controlFocus = ids[next] }
        else if tab { navigatingControls = false; controlFocus = nil; focusRevision += 1 }
    }
    private var acceptsInput: Bool { isEnabled && !browsingFiles && sheet == nil && !playback.showsFailure && scenePhase == .active }
    private func perform(_ command: PlaybackInputCommand) {
        guard acceptsInput else { return }
        #if DEBUG
        commands += 1
        #endif
        PlaybackInputActions(playback: playback, retry: retry, browse: chooseFolder, info: openInfo, home: home).perform(command)
    }
    private func openInfo() {
        guard sheet == nil else { return }
        infoPresentation = playback.beginPresentation(); sheet = .info
    }
    private func closeInfo() {
        if let infoPresentation { playback.endPresentation(infoPresentation) }
        infoPresentation = nil; navigatingControls = false; controlFocus = nil; focusRevision += 1
    }
}

private struct PlaybackControlButton: View {
    let label: String
    let symbol: String
    let id: String
    let requestsFocus: Bool
    let action: () -> Void
    let navigate: (String, Bool) -> Void
    let focusChanged: (Bool) -> Void
    @Environment(\.isEnabled) private var isEnabled
    var body: some View {
        #if targetEnvironment(macCatalyst)
        CatalystPlaybackControl(label: label, symbol: symbol, enabled: isEnabled, requestsFocus: requestsFocus,
            action: action, navigate: navigate, focusChanged: focusChanged).frame(width: 44, height: 44).help(label)
        #else
        Button(action: action) {
            Image(systemName: symbol).font(.title3).frame(minWidth: 44, minHeight: 44)
                .opacity(isEnabled ? 1 : 0.3)
        }
        .buttonStyle(.borderless).keyboardAction(action).accessibilityLabel(label).help(label)
        #endif
    }
}
