import SwiftUI
import UIKit

#if !os(tvOS)
/// The controller is an ancestor of the entire information dialog, including
/// navigation-bar controls. UIKit can route commands without SwiftUI focus.
struct InformationKeyboardHost<Content: View>: UIViewControllerRepresentable {
    let content: Content
    let close: () -> Void

    final class Controller: UIHostingController<Content> {
        var closeInformation: (() -> Void)?
        private var visible = false
        private var requestedClose = false
        override var canBecomeFirstResponder: Bool { true }

        override var keyCommands: [UIKeyCommand]? {
            guard !requestedClose else { return super.keyCommands }
            let closeSelector = #selector(dismissInformation)
            let info = [
                UIKeyCommand(input: "i", modifierFlags: [], action: closeSelector),
                UIKeyCommand(input: "I", modifierFlags: [], action: closeSelector),
                UIKeyCommand(input: "i", modifierFlags: .shift, action: closeSelector)
            ]
            for command in info {
                command.wantsPriorityOverSystemBehavior = true
                command.allowsAutomaticLocalization = false
                command.discoverabilityTitle = "メディア情報を閉じる"
            }
            var commands = info
            #if targetEnvironment(macCatalyst)
            let systemOwnsEscape = MacPlaybackWindowPolicy.fullScreenOwnsEscape
            #else
            let systemOwnsEscape = false
            #endif
            if !systemOwnsEscape {
                commands.append(UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: closeSelector))
            }
            return commands + (super.keyCommands ?? [])
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            visible = true; requestedClose = false
            // Request a responder after presentation, only if content has none.
            // Later updates never take keyboard focus from a control or text selection.
            if !containsFirstResponder(view) { becomeFirstResponder() }
        }
        override func viewWillDisappear(_ animated: Bool) {
            visible = false
            if isFirstResponder { resignFirstResponder() }
            super.viewWillDisappear(animated)
        }
        private func containsFirstResponder(_ view: UIView) -> Bool {
            view.isFirstResponder || view.subviews.contains(where: containsFirstResponder)
        }
        @objc private func dismissInformation() {
            guard visible, !requestedClose else { return }
            requestedClose = true
            closeInformation?()
        }
    }
    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller(rootView: content)
        controller.closeInformation = close
        return controller
    }
    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.rootView = content
        controller.closeInformation = close
    }
    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.closeInformation = nil
        controller.resignFirstResponder()
    }
}
#endif
