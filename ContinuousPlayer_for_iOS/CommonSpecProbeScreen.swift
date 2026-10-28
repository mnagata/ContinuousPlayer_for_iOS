#if DEBUG
import SwiftUI
import UIKit
import Observation
import OSLog

/// Opt-in event observation only. No player, saved folders or production routing.
@MainActor @Observable
private final class CommonSpecProbeEvents {
    private(set) var lines: [String] = []
    private let logger = Logger(subsystem: "jp.nagu.ContinuousPlayer.CommonSpecProbe", category: "Events")

    func record(_ event: String) {
        let line = "\(Date().formatted(date: .omitted, time: .standard)) \(event)"
        lines.append(line)
        if lines.count > 24 { lines.removeFirst(lines.count - 24) }
        logger.notice("\(line, privacy: .public)")
    }
}

struct CommonSpecProbeScreen: View {
    @State private var events = CommonSpecProbeEvents()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Common Spec · OS Event Probe").font(.title2.bold())
                .accessibilityIdentifier("probe.title")
            Text("DEBUG専用：再生や登録は行いません。直近24件を表示し、専用OSログにも出力します。")
                .font(.caption)
            #if os(tvOS)
            Text("下の領域で方向ボタン・スワイプ・決定・戻るを試してください。重複は抑止せず記録します。")
            #else
            Text("下の領域でポインターを動かし3秒停止してください。全画面のEsc、別アプリへの移動、最小化も記録します。")
            #endif
            ProbeInputSurface(events: events)
                .frame(maxWidth: .infinity, minHeight: 100, maxHeight: .infinity)
                .background(.blue.opacity(0.15))
                .accessibilityIdentifier("probe.input")
            ScrollViewReader { proxy in
                ScrollView {
                    Text(events.lines.joined(separator: "\n"))
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("probe.events")
                    Color.clear.frame(height: 1).id("latest")
                }
                .onChange(of: events.lines.last) { _, _ in proxy.scrollTo("latest", anchor: .bottom) }
            }
            .frame(height: 240)
        }
        .padding(24)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase, initial: true) { _, phase in events.record("scenePhase=\(phase)") }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            events.record("application.willResignActive")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            events.record("application.didEnterBackground")
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            events.record("application.didBecomeActive")
        }
        #if os(tvOS)
        .onMoveCommand { events.record("swiftUI.move=\($0)") }
        .onExitCommand { events.record("swiftUI.exit") }
        .onPlayPauseCommand { events.record("swiftUI.playPause") }
        #endif
    }
}

private struct ProbeInputSurface: UIViewRepresentable {
    let events: CommonSpecProbeEvents

    final class InputView: UIView {
        weak var events: CommonSpecProbeEvents?
        #if !os(tvOS)
        private var hideTask: Task<Void, Never>?
        private var hidesPointer = false
        private var lastStyleName: String?
        private lazy var pointer = UIPointerInteraction(delegate: self)
        #endif

        override var canBecomeFirstResponder: Bool { true }
        #if os(tvOS)
        override var canBecomeFocused: Bool { true }
        #endif

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = true
            accessibilityLabel = "OSイベント観測領域"
            for direction: UISwipeGestureRecognizer.Direction in [.left, .right, .up, .down] {
                let swipe = UISwipeGestureRecognizer(target: self, action: #selector(swiped(_:)))
                swipe.direction = direction
                #if os(tvOS)
                swipe.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
                swipe.allowedPressTypes = []
                #endif
                addGestureRecognizer(swipe)
            }
            #if !os(tvOS)
            addInteraction(pointer)
            addGestureRecognizer(UIHoverGestureRecognizer(target: self, action: #selector(hovered(_:))))
            #endif
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { becomeFirstResponder(); events?.record("input.attached") }
            #if !os(tvOS)
            if window == nil { hideTask?.cancel(); hidesPointer = false; pointer.invalidate() }
            #endif
        }

        override var keyCommands: [UIKeyCommand]? {
            let escape = UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(escaped))
            // Observe delivery with normal priority. Do not force it above the OS.
            escape.wantsPriorityOverSystemBehavior = false
            return [escape]
        }

        @objc private func escaped() { events?.record("key.escape.deliveredToApp") }
        @objc private func swiped(_ gesture: UISwipeGestureRecognizer) {
            events?.record("gesture.swipe direction=\(gesture.direction.rawValue) state=\(gesture.state.rawValue)")
        }

        override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses { events?.record("press.began type=\(press.type.rawValue) key=\(press.key?.keyCode.rawValue ?? 0)") }
            super.pressesBegan(presses, with: event)
        }
        override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            for press in presses { events?.record("press.ended type=\(press.type.rawValue)") }
            super.pressesEnded(presses, with: event)
        }
        override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
            events?.record("press.cancelled")
            super.pressesCancelled(presses, with: event)
        }

        #if !os(tvOS)
        @objc private func hovered(_ gesture: UIHoverGestureRecognizer) {
            hideTask?.cancel()
            if hidesPointer { events?.record("pointer.show.requested") }
            hidesPointer = false
            pointer.invalidate()
            guard gesture.state != .ended && gesture.state != .cancelled else {
                events?.record("pointer.exit")
                return
            }
            if gesture.state == .began { events?.record("pointer.enter") }
            hideTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                guard let self else { return }
                self.hidesPointer = true
                self.pointer.invalidate()
                self.events?.record("pointer.hide.requested (3s)")
            }
        }

        func style() -> UIPointerStyle? { hidesPointer ? .hidden() : nil }
        func recordStyle(_ name: String) {
            guard lastStyleName != name else { return }
            lastStyleName = name
            events?.record(name)
        }
        #endif
    }

    func makeUIView(context: Context) -> InputView {
        let view = InputView()
        view.events = events
        return view
    }
    func updateUIView(_ view: InputView, context: Context) { view.events = events }
}

#if !os(tvOS)
extension ProbeInputSurface.InputView: UIPointerInteractionDelegate {
    func pointerInteraction(_ interaction: UIPointerInteraction, regionFor request: UIPointerRegionRequest,
                            defaultRegion: UIPointerRegion) -> UIPointerRegion? {
        UIPointerRegion(rect: bounds, identifier: "common-spec-probe" as NSString)
    }
    func pointerInteraction(_ interaction: UIPointerInteraction, styleFor region: UIPointerRegion) -> UIPointerStyle? {
        let result = style()
        recordStyle(result == nil ? "pointer.style.default" : "pointer.style.hidden")
        return result
    }
}
#endif
#endif
