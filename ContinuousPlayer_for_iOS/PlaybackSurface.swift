import SwiftUI
import AVFoundation
import UIKit

#if targetEnvironment(macCatalyst)
@objc(CPPlaybackPointerProtocol)
protocol MacPlaybackPointer: NSObjectProtocol {
    @objc(startPointerWithHandler:)
    func startPointer(withHandler handler: @escaping (Int, Double, Double, Double, Double, Int, Bool, Double) -> Bool)
    func stopPointer()
    func keyWindowIsFullScreen() -> Bool
    @objc(focusPlaybackToolbarBackwards:video:browse:activate:)
    func focusPlaybackToolbar(backwards: Bool, video: @escaping () -> Void, browse: @escaping () -> Void, activate: @escaping (String) -> Void) -> Bool
    func setPlaybackToolbarIdentifier(_ identifier: String)
    func refreshPlaybackToolbar()
    @objc(preparePlaybackToolbarWithActivation:)
    func preparePlaybackToolbar(activate: @escaping (String) -> Void)
}

enum MacPlaybackWindowPolicy {
    static var fullScreenOwnsEscape: Bool { makeBridge()?.keyWindowIsFullScreen() ?? false }
    static func makeBridge() -> (any MacPlaybackPointer)? {
        guard let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("MacPlaybackLifecycle.bundle"),
              let type = Bundle(url: url)?.principalClass as? NSObject.Type else { return nil }
        return type.init() as? any MacPlaybackPointer
    }
}
#endif

/// Raw contact ownership avoids tap/swipe recognizers acting on the same input.
/// Keyboard ownership follows native focus and is released for controls/modal UI.
struct PlaybackSurface: UIViewRepresentable {
    let player: AVPlayer
    var enabled = true
    var focusRevision = 0
    var playing = false
    var canSeek = false
    var onCommand: (PlaybackInputCommand) -> Void

    final class Surface: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
        var enabled = false {
            didSet {
                if !enabled { heldKeys.removeAll(); if isFirstResponder { resignFirstResponder() } }
                else if !oldValue { requestKeyboardFocus() }
            }
        }
        override var canBecomeFirstResponder: Bool { enabled }
        override var canBecomeFocused: Bool { enabled }
        private var heldKeys: Set<UIKeyboardHIDUsage> = []
        var focusRevision = -1
        private var focusTask: Task<Void, Never>?
        func requestKeyboardFocus() {
            focusTask?.cancel()
            focusTask = Task { @MainActor [weak self] in
                await Task.yield()
                if !Task.isCancelled { self?.focusKeyboard() }
            }
        }
        func focusKeyboard() {
            guard enabled, window?.isKeyWindow == true else { return }
            #if targetEnvironment(macCatalyst)
            if MacPlaybackWindowPolicy.fullScreenOwnsEscape { window?.windowScene?.titlebar?.autoHidesToolbarInFullScreen = true }
            #endif
            becomeFirstResponder()
            if let system = UIFocusSystem.focusSystem(for: self) {
                system.requestFocusUpdate(to: self); system.updateFocusIfNeeded()
            }
        }
        override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
            super.didUpdateFocus(in: context, with: coordinator)
            if context.nextFocusedView === self { becomeFirstResponder() }
            else if context.previouslyFocusedView === self { heldKeys.removeAll(); resignFirstResponder() }
        }
        private func command(for key: UIKey) -> PlaybackInputCommand? {
            guard enabled, isFirstResponder,
                  key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty else { return nil }
            #if targetEnvironment(macCatalyst)
            if key.inputName == "escape" && MacPlaybackWindowPolicy.fullScreenOwnsEscape { return nil }
            #endif
            return PlaybackKeyboardInput.command(key.inputName, shift: key.modifierFlags.contains(.shift))
        }
        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            focusTask?.cancel()
            var remaining = presses
            for press in presses {
                #if targetEnvironment(macCatalyst)
                if let key = press.key, key.keyCode == .keyboardTab,
                   key.modifierFlags.intersection([.command, .control, .alternate]).isEmpty {
                    focusTask?.cancel()
                    if MacPlaybackWindowPolicy.fullScreenOwnsEscape { window?.windowScene?.titlebar?.autoHidesToolbarInFullScreen = false }
                    resignFirstResponder()
                    if let identifier = window?.windowScene?.titlebar?.toolbar?.identifier {
                        bridge?.setPlaybackToolbarIdentifier(identifier)
                    }
                    let handled = bridge?.focusPlaybackToolbar(backwards: key.modifierFlags.contains(.shift),
                       video: { [weak self] in self?.resignFirstResponder(); self?.window?.makeKey(); self?.focusKeyboard() },
                       browse: { [weak self] in self?.onCommand?(.browse) },
                       activate: { [weak self] identifier in
                           let commands: [String: PlaybackInputCommand] = ["playback.home": .home, "playback.folder": .browse,
                               "playback.info": .info, "playback.playPause": .toggle]
                           if let command = commands[identifier] { self?.onCommand?(command) }
                       }) == true
                    if handled { heldKeys.insert(.keyboardTab); remaining.remove(press); continue }
                    becomeFirstResponder()
                }
                #endif
                guard let key = press.key, let command = command(for: key) else { continue }
                remaining.remove(press)
                if heldKeys.insert(key.keyCode).inserted { onCommand?(command) }
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
        var onCommand: ((PlaybackInputCommand) -> Void)?
        private var input = PlaybackTouchInput()
        #if targetEnvironment(macCatalyst)
        private var bridge: (any MacPlaybackPointer)?
        private var trackingPointer = false
        override func didMoveToWindow() {
            super.didMoveToWindow()
            focusKeyboard()
            if window == nil { stop(); return }
            guard bridge == nil, let bridge = MacPlaybackWindowPolicy.makeBridge() else { return }
            self.bridge = bridge
            bridge.startPointer { [weak self] phase, x, y, width, height, count, active, time in
                MainActor.assumeIsolated {
                    guard let self else { return false }
                    if phase == 0 { self.trackingPointer = false; self.input.cancel() }
                    guard self.enabled, let window = self.window, window.isKeyWindow, active, width > 0, height > 0,
                          window.rootViewController?.presentedViewController == nil else { return false }
                    let point = CGPoint(x: x / width * window.bounds.width, y: y / height * window.bounds.height)
                    let local = self.convert(point, from: window)
                    let hit = window.hitTest(point, with: nil)
                    let background = self.bounds.contains(local) && (hit === self || hit?.isDescendant(of: self) == true)
                    switch phase {
                    case 0:
                        guard background else { return false }
                        self.trackingPointer = true
                        self.input.begin(at: local, time: time, source: .pointer, activeWindow: active)
                    case 1:
                        if self.trackingPointer { self.input.move(to: local) }
                    default:
                        guard self.trackingPointer else { return false }
                        self.trackingPointer = false
                        if let command = self.input.end(at: local, time: time, width: self.bounds.width, clickCount: count) {
                            self.focusKeyboard(); self.onCommand?(command)
                            return true
                        }
                        return background && active && count > 1
                    }
                    return false
                }
            }
        }
        func stop() { bridge?.stopPointer(); bridge = nil; input.cancel(); trackingPointer = false }
        func cancelContact() { input.cancel(); trackingPointer = false }
        isolated deinit { bridge?.stopPointer() }
        #else
        private var contact: UITouch?
        override func didMoveToWindow() { super.didMoveToWindow(); focusKeyboard() }
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard enabled, let touch = touches.first else { return }
            if event?.buttonMask.contains(.secondary) == true { return }
            if contact != nil || touches.count != 1 || (event?.allTouches?.count ?? 1) > 1 {
                input.cancel(); contact = nil
                return
            }
            guard touch.type == .direct || touch.type == .indirectPointer else { return }
            contact = touch
            input.begin(at: touch.location(in: self), time: touch.timestamp,
                        source: touch.type == .direct ? .direct : .pointer,
                        activeWindow: window?.isKeyWindow == true)
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            if let contact { input.move(to: contact.location(in: self)) }
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let contact, touches.contains(contact) else { return }
            self.contact = nil
            guard enabled else { input.cancel(); return }
            if let command = input.end(at: contact.location(in: self), time: contact.timestamp,
                                       width: bounds.width, clickCount: contact.tapCount) { focusKeyboard(); onCommand?(command) }
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { contact = nil; input.cancel() }
        func stop() { contact = nil; input.cancel() }
        func cancelContact() { contact = nil; input.cancel() }
        #endif
        override func accessibilityActivate() -> Bool {
            guard enabled else { return false }
            onCommand?(.toggle); return true
        }
    }
    func makeUIView(context: Context) -> Surface {
        let view = Surface()
        view.playerLayer.videoGravity = .resizeAspect
        view.isMultipleTouchEnabled = true
        view.isAccessibilityElement = true
        view.accessibilityIdentifier = "player.video"
        view.accessibilityTraits = .button
        return view
    }
    func updateUIView(_ view: Surface, context: Context) {
        view.playerLayer.player = player
        if !enabled { view.cancelContact() }
        view.enabled = enabled
        if view.focusRevision != focusRevision { view.focusRevision = focusRevision; view.requestKeyboardFocus() }
        view.onCommand = onCommand
        view.accessibilityLabel = playing ? "一時停止" : "再生"
        let actions: [(String, PlaybackInputCommand)] = [("前のファイル", .previous), ("次のファイル", .next),
            ("ファイル一覧", .browse), ("メディア情報", .info)] + (canSeek ? [("10秒戻す", .backward), ("10秒進める", .forward)] : [])
        view.accessibilityCustomActions = actions.map { name, command in
            UIAccessibilityCustomAction(name: name) { [weak view] _ in
                guard let view, view.enabled else { return false }
                view.onCommand?(command); return true
            }
        }
    }
    static func dismantleUIView(_ view: Surface, coordinator: ()) { view.stop(); view.onCommand = nil; view.playerLayer.player = nil }
}
