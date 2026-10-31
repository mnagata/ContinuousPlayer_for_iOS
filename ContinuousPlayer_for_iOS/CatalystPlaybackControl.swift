#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Crossing the AppKit toolbar boundary needs an actual UIKit responder. A
/// SwiftUI FocusState alone can lose its request while the responder is changing.
struct CatalystPlaybackControl: UIViewRepresentable {
    let label: String
    let symbol: String
    let enabled: Bool
    let requestsFocus: Bool
    let action: () -> Void
    let navigate: (String, Bool) -> Void
    let focusChanged: (Bool) -> Void

    final class Control: UIButton {
        var activate: (() -> Void)?
        var navigate: ((String, Bool) -> Void)?
        var focusChanged: ((Bool) -> Void)?
        var requested = false
        var focusTask: Task<Void, Never>?
        private var heldKeys: Set<UIKeyboardHIDUsage> = []
        override var canBecomeFirstResponder: Bool { isEnabled }
        override var canBecomeFocused: Bool { isEnabled }
        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { layer.cornerRadius = 8; layer.borderWidth = 2; layer.borderColor = UIColor.cyan.cgColor }
            return accepted
        }
        override func resignFirstResponder() -> Bool {
            layer.borderWidth = 0
            return super.resignFirstResponder()
        }
        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)
            if context.nextFocusedView === self { _ = becomeFirstResponder(); focusChanged?(true) }
            else if context.previouslyFocusedView === self { _ = resignFirstResponder(); heldKeys.removeAll(); focusChanged?(false) }
        }
        func requestFocus() {
            focusTask?.cancel()
            focusTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, !Task.isCancelled, self.requested, self.isEnabled, self.window?.isKeyWindow == true else { return }
                _ = self.becomeFirstResponder()
                if let system = UIFocusSystem.focusSystem(for: self) {
                    system.requestFocusUpdate(to: self); system.updateFocusIfNeeded()
                }
                self.focusChanged?(true)
            }
        }
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            var remaining = presses
            for press in presses {
                guard isEnabled, let key = press.key,
                      key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty else { continue }
                let name = key.inputName
                guard ["left", "right", "up", "down", "\t", "return", " ", "escape"].contains(name) || key.keyCode == .keyboardTab else { continue }
                if name == "escape" && MacPlaybackWindowPolicy.fullScreenOwnsEscape { continue }
                remaining.remove(press)
                guard heldKeys.insert(key.keyCode).inserted else { continue }
                if name == "return" || name == " " { activate?() }
                else { navigate?(key.keyCode == .keyboardTab ? "tab" : name, key.modifierFlags.contains(.shift)) }
            }
            if !remaining.isEmpty { super.pressesBegan(remaining, with: event) }
        }
        override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let remaining = Set(presses.filter { $0.key.map { !heldKeys.contains($0.keyCode) } ?? true })
            if !remaining.isEmpty { super.pressesChanged(remaining, with: event) }
        }
        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            let remaining = Set(presses.filter { $0.key.map { heldKeys.remove($0.keyCode) == nil } ?? true })
            if !remaining.isEmpty { super.pressesEnded(remaining, with: event) }
        }
        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            heldKeys.removeAll(); super.pressesCancelled(presses, with: event)
        }
        @objc func clicked() { if isEnabled { activate?() } }
    }
    func makeUIView(context: Context) -> Control {
        let button = Control(type: .system)
        button.addTarget(button, action: #selector(Control.clicked), for: .touchUpInside)
        button.isPointerInteractionEnabled = true
        return button
    }
    func updateUIView(_ button: Control, context: Context) {
        button.activate = action; button.navigate = navigate; button.focusChanged = focusChanged
        button.isEnabled = enabled; button.alpha = enabled ? 1 : 0.3
        button.tintColor = .white
        button.setImage(UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        button.accessibilityLabel = label
        button.accessibilityIdentifier = symbol == "play.fill" || symbol == "pause.fill" ? "player.toggle" : symbol
        let needsFocus = requestsFocus && !button.requested
        button.requested = requestsFocus
        if needsFocus { button.requestFocus() }
        else if !requestsFocus && button.isFirstResponder { _ = button.resignFirstResponder() }
    }
    static func dismantleUIView(_ button: Control, coordinator: ()) {
        button.focusTask?.cancel(); button.activate = nil; button.navigate = nil; button.focusChanged = nil
        _ = button.resignFirstResponder()
    }
}
#endif
