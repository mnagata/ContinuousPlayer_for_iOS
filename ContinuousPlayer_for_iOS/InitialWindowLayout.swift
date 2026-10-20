import Foundation
import CoreGraphics

nonisolated enum InitialWindowLayout {
    /// Fit a 16:9 content area plus window chrome within 60% of the display.
    static func frame(in screen: CGRect, titlebarHeight: CGFloat) -> CGRect {
        let chrome = max(0, titlebarHeight)
        let availableHeight = max(0, screen.height * 0.6 - chrome)
        let maximumWidth = min(screen.width * 0.6, availableHeight * 16 / 9)
        // Whole 16:9 units avoid rounding the content to a different aspect ratio.
        let width = floor(maximumWidth / 16) * 16
        let size = CGSize(width: width, height: width * 9 / 16 + chrome)
        return CGRect(x: screen.midX - size.width / 2,
                      y: screen.midY - size.height / 2,
                      width: size.width, height: size.height)
    }
}

#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit
import OSLog

/// SwiftUI's display-aware window placement API is unavailable on Mac Catalyst.
struct CatalystInitialWindowSizing: UIViewControllerRepresentable {
    final class Controller: UIViewController {
        private var hasSizedWindow = false
        private var pendingInitialFrame: CGRect?

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            guard let pending = pendingInitialFrame, let window = view.window,
                  let scene = window.windowScene, window.bounds.width > 0 else { return }
            let frame = scene.effectiveGeometry.systemFrame
            guard abs(frame.width - pending.width) < 2, abs(frame.height - pending.height) < 2 else { return }

            // The first native resize establishes Catalyst's UIKit-to-Mac scale.
            // Convert the title bar only after both coordinate spaces have updated.
            pendingInitialFrame = nil
            let scale = frame.width / window.bounds.width
            let chrome = max(0, ((window.bounds.height - view.bounds.height) * scale).rounded())
            let target = InitialWindowLayout.frame(in: scene.screen.bounds, titlebarHeight: chrome)
            if target.size != frame.size {
                // UIKit can supersede geometry requests made inside a layout pass.
                DispatchQueue.main.async { [weak self, weak scene] in
                    guard let scene else { return }
                    self?.requestFrame(target, in: scene, titlebarHeight: chrome)
                }
            }
        }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            sizeWindowIfReady()
        }

        private func sizeWindowIfReady() {
            guard !hasSizedWindow, let window = view.window, let scene = window.windowScene else { return }
            // Use the window's display in points, rather than Retina pixel counts.
            let display = scene.screen.bounds
            guard display.width > 0, display.height > 0 else { return }
            let chrome = max(0, window.bounds.height - view.bounds.height)
            let target = InitialWindowLayout.frame(in: display, titlebarHeight: chrome)

            // Set before requesting a layout change; later resizes belong to the user.
            hasSizedWindow = true
            pendingInitialFrame = target
            requestFrame(target, in: scene, titlebarHeight: chrome)
        }

        private func requestFrame(_ target: CGRect, in scene: UIWindowScene, titlebarHeight: CGFloat) {
            Logger(subsystem: "jp.nagu.ContinuousPlayer-for-Mac", category: "WindowSizing")
                .notice("Initial window sizing: chrome=\(titlebarHeight, privacy: .public), target=\(String(describing: target), privacy: .public)")
            scene.requestGeometryUpdate(.Mac(systemFrame: target)) { [weak self] error in
                self?.pendingInitialFrame = nil
                Logger(subsystem: "jp.nagu.ContinuousPlayer-for-Mac", category: "WindowSizing")
                    .error("Initial window sizing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { }
}
#endif
