import SwiftUI
import UIKit

/// The same four recovery actions are available on every Apple player.
struct PlaybackFailurePanel: View {
    let playback: PlaybackController
    let retry: () -> Void
    let browse: () -> Void
    @FocusState private var focus: Action?
    private enum Action: Hashable { case retry, next, browse, close }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let failure = playback.failure {
                        Text("再生できません").font(.title2.bold())
                        Text(failure.name).font(.headline)
                        Text(failure.reason).foregroundStyle(.orange)
                        Text(failure.guidance).font(.callout)
                        Text("再試行位置: \(String(format: "%.1f", failure.seconds))秒")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("再試行", action: retry)
                            .keyboardAction(retry)
                            .disabled(!playback.canRetry)
                            .focused($focus, equals: .retry)
                            .accessibilityIdentifier("player.error.retry")
                        if playback.state.canGoForward {
                            Button("次のファイル", action: playback.nextAfterFailure)
                                .keyboardAction(playback.nextAfterFailure)
                                .focused($focus, equals: .next)
                                .accessibilityIdentifier("player.error.next")
                        }
                        Button("ファイル一覧") { playback.dismissFailure(); browse() }
                            .keyboardAction { playback.dismissFailure(); browse() }
                            .focused($focus, equals: .browse)
                            .accessibilityIdentifier("player.error.browse")
                        Button("閉じる", action: playback.dismissFailure)
                            .keyboardAction(playback.dismissFailure)
                            .focused($focus, equals: .close)
                            .accessibilityIdentifier("player.error.close")
                    }
                }
                .frame(maxWidth: panelWidth, alignment: .leading)
                .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding(24).frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.center)
        }
        .buttonStyle(.bordered)
        .accessibilityElement(children: .contain).accessibilityAddTraits(.isModal)
        .accessibilityIdentifier("player.error")
        .task(id: playback.canRetry) { focus = playback.canRetry ? .retry : (playback.state.canGoForward ? .next : .browse) }
        #if os(tvOS)
        .onExitCommand(perform: playback.dismissFailure)
        #else
        .modifier(ModalDismissKeys(inputs: ["escape"], close: playback.dismissFailure))
        #endif
    }
    private var panelWidth: CGFloat {
        #if os(tvOS)
        1000
        #else
        620
        #endif
    }
}

/// Only a fresh key-down dismisses a modal. Repeats from the key that opened
/// it are consumed without closing it or leaking back into the player.
struct ModalDismissKeys: ViewModifier {
    var inputs = ["i", "escape"]
    let close: () -> Void
    func body(content: Content) -> some View {
        content.onKeyPress(keys: [.escape, "i"], phases: [.down, .repeat]) { key in
            guard !key.hasCommandModifiers, inputs.contains(key.inputName) else { return .ignored }
            #if targetEnvironment(macCatalyst)
            if key.inputName == "escape" && MacPlaybackWindowPolicy.fullScreenOwnsEscape { return .ignored }
            #endif
            if key.phase == .down { close() }
            return .handled
        }
    }
}
