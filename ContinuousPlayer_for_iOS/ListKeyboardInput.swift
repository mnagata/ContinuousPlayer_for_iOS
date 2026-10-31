import SwiftUI
import UIKit

#if !os(tvOS)
/// This responder belongs only to the visible list. A focus revision requests
/// the selected row again; ordinary updates never take focus from a control.
struct ListKeyboardInput: UIViewRepresentable {
    let enabled: Bool
    let revision: Int
    let handle: (String, Bool) -> Bool
    final class Receiver: UIView {
        var enabled = false
        var revision = -1
        var held: Set<UIKeyboardHIDUsage> = []
        var handle: ((String, Bool) -> Bool)?
        var focusTask: Task<Void, Never>?
        private static let navigationInputs = [
            UIKeyCommand.inputUpArrow: "up", UIKeyCommand.inputDownArrow: "down",
            UIKeyCommand.inputLeftArrow: "left", UIKeyCommand.inputRightArrow: "right",
            UIKeyCommand.inputPageUp: "pageUp", UIKeyCommand.inputPageDown: "pageDown"
        ]
        private lazy var navigationCommands: [UIKeyCommand] = Self.navigationInputs.map { input, name in
            let command = UIKeyCommand(action: #selector(moveSelection(_:)), input: input, propertyList: name)
            command.wantsPriorityOverSystemBehavior = true
            command.repeatBehavior = .repeatable
            return command
        }
        override var keyCommands: [UIKeyCommand]? { enabled ? navigationCommands : nil }
        override var canBecomeFirstResponder: Bool { enabled }
        override var canBecomeFocused: Bool { enabled }
        func focusList() {
            guard enabled, !isFirstResponder, window?.isKeyWindow == true else { return }
            becomeFirstResponder()
        }
        @objc private func moveSelection(_ command: UIKeyCommand) {
            guard enabled, isFirstResponder, window?.isKeyWindow == true,
                  let name = command.propertyList as? String else { return }
            _ = handle?(name, false)
        }
        override func didMoveToWindow() { super.didMoveToWindow(); focusList() }
        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)
            if context.nextFocusedView === self { focusList() }
            else if context.previouslyFocusedView === self { held.removeAll(); resignFirstResponder() }
        }
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var remaining = presses
            for press in presses {
                guard enabled, isFirstResponder, let key = press.key,
                      key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty else { continue }
                // Navigation is owned by repeatable key commands, never both input paths.
                if Self.navigationInputs[key.charactersIgnoringModifiers] != nil { continue }
                let repeating = held.contains(key.keyCode)
                if handle?(key.inputName, repeating) == true {
                    held.insert(key.keyCode); remaining.remove(press)
                }
            }
            if !remaining.isEmpty { super.pressesBegan(remaining, with: event) }
        }
        override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let remaining = Set(presses.filter { $0.key.map { !held.contains($0.keyCode) } ?? true })
            if !remaining.isEmpty { super.pressesChanged(remaining, with: event) }
        }
        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let remaining = Set(presses.filter { $0.key.map { held.remove($0.keyCode) == nil } ?? true })
            if !remaining.isEmpty { super.pressesEnded(remaining, with: event) }
        }
        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            held.removeAll(); super.pressesCancelled(presses, with: event)
        }
    }
    func makeUIView(context: Context) -> Receiver { Receiver() }
    func updateUIView(_ view: Receiver, context: Context) {
        let request = enabled && (!view.enabled || view.revision != revision)
        view.enabled = enabled; view.revision = revision; view.handle = handle
        if !enabled { view.held.removeAll(); if view.isFirstResponder { view.resignFirstResponder() } }
        else if request {
            view.focusTask?.cancel()
            view.focusTask = Task { @MainActor [weak view] in
                await Task.yield()
                if !Task.isCancelled { view?.focusList() }
            }
        }
    }
    static func dismantleUIView(_ view: Receiver, coordinator: ()) { view.focusTask?.cancel(); view.enabled = false; view.handle = nil; view.resignFirstResponder() }
}
#endif

extension UIKey {
    var inputName: String {
        switch keyCode {
        case .keyboardLeftArrow: "left"
        case .keyboardRightArrow: "right"
        case .keyboardUpArrow: "up"
        case .keyboardDownArrow: "down"
        case .keyboardReturnOrEnter, .keypadEnter: "return"
        case .keyboardEscape: "escape"
        case .keyboardDeleteOrBackspace: "backspace"
        case .keyboardPageUp: "pageUp"
        case .keyboardPageDown: "pageDown"
        default: charactersIgnoringModifiers.lowercased()
        }
    }
}
