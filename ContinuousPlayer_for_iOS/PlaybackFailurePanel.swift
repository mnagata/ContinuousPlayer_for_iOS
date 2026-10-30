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
                            .disabled(!playback.canRetry)
                            .focused($focus, equals: .retry)
                            .accessibilityIdentifier("player.error.retry")
                        if playback.state.canGoForward {
                            Button("次のファイル", action: playback.nextAfterFailure)
                                .focused($focus, equals: .next)
                                .accessibilityIdentifier("player.error.next")
                        }
                        Button("ファイル一覧") { playback.dismissFailure(); browse() }
                            .focused($focus, equals: .browse)
                            .accessibilityIdentifier("player.error.browse")
                        Button("閉じる", action: playback.dismissFailure)
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
        .background(ModalDismissKeyboardCommands(inputs: [UIKeyCommand.inputEscape], close: playback.dismissFailure))
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

/// Keep modal dismissal on its own responder; transport keys stay with the UI.
struct ModalDismissKeyboardCommands: UIViewControllerRepresentable {
    var inputs = ["i", UIKeyCommand.inputEscape]
    let close: () -> Void
    final class Controller: UIViewController {
        var close: (() -> Void)?
        var inputs: [String] = []
        override var canBecomeFirstResponder: Bool { true }
        override var keyCommands: [UIKeyCommand]? {
            inputs.map { input in
                let command = UIKeyCommand(input: input, modifierFlags: [], action: #selector(closeModal))
                command.wantsPriorityOverSystemBehavior = true
                return command
            }
        }
        override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); becomeFirstResponder() }
        override func viewWillDisappear(_ animated: Bool) { resignFirstResponder(); super.viewWillDisappear(animated) }
        @objc private func closeModal() { close?() }
    }
    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.view.isUserInteractionEnabled = false
        controller.close = close; controller.inputs = inputs
        return controller
    }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.close = close; controller.inputs = inputs }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.resignFirstResponder(); controller.close = nil
    }
}
