import SwiftUI
import UIKit
import OSLog

extension View {
    func playbackSceneLifecycle(session: PlaybackSessionCoordinator, onEnd: (() -> Void)? = nil) -> some View {
        modifier(PlaybackSceneLifecycle(session: session, onEnd: onEnd))
    }
}

private struct PlaybackSceneLifecycle: ViewModifier {
    let session: PlaybackSessionCoordinator
    let onEnd: (() -> Void)?
    func body(content: Content) -> some View {
        content.background(PlaybackSceneObserver(session: session, onEnd: onEnd).frame(width: 0, height: 0))
    }
}

#if targetEnvironment(macCatalyst)
@objc(CPPlaybackLifecycleProtocol)
protocol PlaybackMacLifecycle: NSObjectProtocol {
    @objc(startWithHandler:)
    func start(withHandler handler: @escaping (String, Bool) -> Void)
    func stop()
}
#endif

private struct PlaybackSceneObserver: UIViewControllerRepresentable {
    let session: PlaybackSessionCoordinator
    let onEnd: (() -> Void)?

    final class Controller: UIViewController {
        var session: PlaybackSessionCoordinator?
        var onEnd: (() -> Void)?
        func end() { if let onEnd { onEnd() } else { session?.end() } }
        private var observers: [NSObjectProtocol] = []
        private weak var observedScene: UIWindowScene?
        #if targetEnvironment(macCatalyst)
        private var macLifecycle: (any PlaybackMacLifecycle)?
        #endif

        override func loadView() { view = UIView(); view.isUserInteractionEnabled = false }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard observers.isEmpty, let scene = view.window?.windowScene else { return }
            observedScene = scene
            let center = NotificationCenter.default
            #if !os(tvOS) && !targetEnvironment(macCatalyst)
            let keepsInactive = UIDevice.current.userInterfaceIdiom == .pad
            #endif
            #if os(tvOS)
            // tvOS follows the foreground application's activity and has no
            // desktop multiwindow input-focus exception.
            session?.setSceneAllowsPlayback(UIApplication.shared.applicationState == .active)
            for (name, allowed) in [(UIApplication.didBecomeActiveNotification, true),
                                    (UIApplication.willResignActiveNotification, false),
                                    (UIApplication.didEnterBackgroundNotification, false)] {
                observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.session?.setSceneAllowsPlayback(allowed) }
                })
            }
            #elseif targetEnvironment(macCatalyst)
            // A visible Mac window can enter a UIKit background/inactive state
            // while moving between full-screen Spaces. Native window minimization,
            // app Hide and workspace sleep/lock are the actual stop conditions.
            session?.setSceneAllowsPlayback(true)
            observers.append(center.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.session?.setSceneAllowsPlayback(true) }
            })
            observers.append(center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    // Retain the conservative fallback if the native bundle fails.
                    guard let self, self.macLifecycle == nil else { return }
                    self.session?.setSceneAllowsPlayback(false)
                }
            })
            #else
            session?.setSceneAllowsPlayback(scene.activationState == .foregroundActive ||
                (keepsInactive && scene.activationState == .foregroundInactive))
            // Observe the actual window scene even while the owning home view is
            // covered by a player/picker. A covered view's environment can lag.
            observers.append(center.addObserver(forName: UIScene.didActivateNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.session?.setSceneAllowsPlayback(true) }
            })
            observers.append(center.addObserver(forName: UIScene.didEnterBackgroundNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.session?.setSceneAllowsPlayback(false) }
            })
            #if !targetEnvironment(macCatalyst)
            if !keepsInactive {
                observers.append(center.addObserver(forName: UIScene.willDeactivateNotification, object: scene, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.session?.setSceneAllowsPlayback(false) }
                })
            }
            #endif
            #endif
            observers.append(center.addObserver(forName: UIScene.didDisconnectNotification, object: scene, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.end() }
            })
            observers.append(center.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.end() }
            })
            observers.append(center.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.session?.setBlocked("protected-data", true) }
            })
            observers.append(center.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.session?.setBlocked("protected-data", false) }
            })
            #if targetEnvironment(macCatalyst)
            if let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("MacPlaybackLifecycle.bundle"),
               let bundle = Bundle(url: url), let type = bundle.principalClass as? NSObject.Type,
               let bridge = type.init() as? any PlaybackMacLifecycle {
                macLifecycle = bridge
                bridge.start { [weak self] reason, blocked in
                    MainActor.assumeIsolated { self?.session?.setBlocked(reason, blocked) }
                }
                Logger(subsystem: "jp.nagu.ContinuousPlayer-for-Mac", category: "Lifecycle")
                    .notice("Mac lifecycle bridge loaded")
            } else {
                Logger(subsystem: "jp.nagu.ContinuousPlayer-for-Mac", category: "Lifecycle")
                    .fault("MacPlaybackLifecycle.bundle could not be loaded")
            }
            #endif
        }

        isolated deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            #if targetEnvironment(macCatalyst)
            macLifecycle?.stop()
            #endif
        }
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.session = session
        controller.onEnd = onEnd
        return controller
    }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.session = session; controller.onEnd = onEnd }
}
