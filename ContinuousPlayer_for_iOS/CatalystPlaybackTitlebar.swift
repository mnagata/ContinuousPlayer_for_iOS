#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Owns the native title and toolbar only for the lifetime of this window's player.
struct CatalystPlaybackTitlebar: UIViewControllerRepresentable {
    let filename: String
    let status: String?
    let controlsVisible: Bool
    let fullScreen: Bool
    let cursorHidden: Bool
    let actionsEnabled: Bool
    let home: () -> Void
    let chooseFolder: () -> Void
    let showInfo: () -> Void
    let onPointerActivity: () -> Void
    let onFullScreenChange: (Bool) -> Void
    let onToolbarFocusChange: (Bool) -> Void
    let onToolbarHoverChange: (Bool) -> Void
    let onToolbarExit: (Bool) -> Void
    let onWindowMinimizedChange: (Bool) -> Void

    final class Controller: UIViewController, NSToolbarDelegate {
        var configuration: CatalystPlaybackTitlebar? {
            didSet { scheduleTitlebarUpdate() }
        }

        private var pendingUpdate: Task<Void, Never>?
        private func scheduleTitlebarUpdate() {
            pendingUpdate?.cancel()
            pendingUpdate = Task { @MainActor [weak self] in
                await Task.yield()
                if !Task.isCancelled { self?.updateTitlebar() }
            }
        }
        func cancelPendingUpdate() { pendingUpdate?.cancel(); pendingUpdate = nil }

        private static let homeID = NSToolbarItem.Identifier("playback.home")
        private static let folderID = NSToolbarItem.Identifier("playback.folder")
        private static let infoID = NSToolbarItem.Identifier("playback.info")
        private static let fullScreenID = NSToolbarItem.Identifier("playback.fullScreen")
        private let toolbarIdentifier = "ContinuousPlayer.Playback.\(UUID().uuidString)"
        private let keyboardBridge = MacPlaybackWindowPolicy.makeBridge()
        private weak var scene: UIWindowScene?
        private var previousTitle = "ContinuousPlayer"
        private var appliedTitle: String?
        private var previousToolbar: NSToolbar?
        private var previousStyle: UITitlebarToolbarStyle = .automatic
        private var previousAutoHide = false

        private lazy var playbackToolbar: NSToolbar = {
            let toolbar = NSToolbar(identifier: NSToolbar.Identifier(toolbarIdentifier))
            toolbar.delegate = self
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            toolbar.allowsDisplayModeCustomization = false
            return toolbar
        }()

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateTitlebar()
            DispatchQueue.main.async { [weak self] in self?.updateTitlebar() }
        }

        private func updateTitlebar() {
            guard let configuration, let windowScene = viewIfLoaded?.window?.windowScene,
                  let titlebar = windowScene.titlebar else { return }
            if scene !== windowScene {
                restoreTitlebar()
                scene = windowScene
                previousTitle = windowScene.title ?? "ContinuousPlayer"
                previousToolbar = titlebar.toolbar
                previousStyle = titlebar.toolbarStyle
                previousAutoHide = titlebar.autoHidesToolbarInFullScreen
                titlebar.toolbarStyle = .unifiedCompact
                titlebar.autoHidesToolbarInFullScreen = true
                titlebar.toolbar = playbackToolbar
                keyboardBridge?.setPlaybackToolbarIdentifier(toolbarIdentifier)

            }

            let name = MediaDisplayName.title(configuration.filename)
            let title = (name.isEmpty ? "ContinuousPlayer" : name) + (configuration.status.map { " · " + $0 } ?? "")
            // Full screen uses the same in-content top bar as the other platforms.
            // Never show duplicate toolbar actions there.
            playbackToolbar.isVisible = !configuration.fullScreen
            titlebar.autoHidesToolbarInFullScreen = true
            keyboardBridge?.setPlaybackCursorHidden(configuration.cursorHidden)
            keyboardBridge?.setPlaybackToolbarExitHandler(configuration.onToolbarExit)
            windowScene.title = title
            appliedTitle = title
            for item in playbackToolbar.items { configure(item) }
            keyboardBridge?.setPlaybackToolbarIdentifier(toolbarIdentifier)
            keyboardBridge?.preparePlaybackToolbar { [weak self] identifier in
                guard let self, let config = self.configuration, config.actionsEnabled else { return }
                switch identifier {
                case "playback.home": config.home()
                case "playback.folder": config.chooseFolder()
                case "playback.info": config.showInfo()
                case "playback.fullScreen": self.keyboardBridge?.togglePlaybackFullScreen()
                default: break
                }
            }
            keyboardBridge?.startPlaybackChrome { [weak self] kind, value in
                guard let config = self?.configuration else { return }
                switch kind {
                case 0: config.onPointerActivity()
                case 1: config.onFullScreenChange(value)
                case 2: config.onToolbarFocusChange(value)
                case 3: config.onToolbarHoverChange(value)
                case 4: config.onWindowMinimizedChange(value)
                default: break
                }
            }
            keyboardBridge?.setPlaybackToolbarControlsVisible(configuration.controlsVisible)
        }

        func restoreTitlebar(restoringHome: Bool = false) {
            keyboardBridge?.stopPlaybackChrome()
            if let scene {
                configuration?.onWindowMinimizedChange(false)
                if restoringHome { scene.title = "ContinuousPlayer" }
                else if scene.title == appliedTitle { scene.title = previousTitle }
                if let titlebar = scene.titlebar, titlebar.toolbar === playbackToolbar {
                    titlebar.toolbar = previousToolbar
                    titlebar.toolbarStyle = previousStyle
                    titlebar.autoHidesToolbarInFullScreen = previousAutoHide
                }
            }
            scene = nil
            appliedTitle = nil
            previousToolbar = nil
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [.flexibleSpace, Self.homeID, Self.folderID, Self.infoID, Self.fullScreenID]
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }

        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            guard [Self.homeID, Self.folderID, Self.infoID, Self.fullScreenID].contains(identifier) else { return nil }
            let item = NSToolbarItem(itemIdentifier: identifier)
            item.target = self
            item.autovalidates = false
            configure(item)
            return item
        }

        private func configure(_ item: NSToolbarItem) {
            guard let configuration else { return }
            let label: String
            let symbol: String
            switch item.itemIdentifier {
            case Self.homeID:
                label = "ホームに戻る"
                symbol = "house"
                item.action = #selector(goHome)
            case Self.folderID:
                label = "ファイル一覧"
                symbol = "folder"
                item.action = #selector(browseFiles)
            case Self.infoID:
                label = "メディア情報"
                symbol = "info.circle"
                item.action = #selector(showInfo)
            case Self.fullScreenID:
                label = "全画面にする"
                symbol = "arrow.up.left.and.arrow.down.right"
                item.action = #selector(toggleFullScreen)
            default:
                return
            }
            item.label = label
            item.paletteLabel = label
            item.toolTip = label
            item.image = UIImage(systemName: symbol)
            item.isEnabled = configuration.actionsEnabled
        }

        @objc private func goHome() {
            guard let configuration, configuration.actionsEnabled else { return }
            configuration.home()
        }

        @objc private func browseFiles() {
            guard let configuration, configuration.actionsEnabled else { return }
            configuration.chooseFolder()
        }

        @objc private func showInfo() {
            guard let configuration, configuration.actionsEnabled else { return }
            configuration.showInfo()
        }

        @objc private func toggleFullScreen() {
            guard configuration?.actionsEnabled == true else { return }
            keyboardBridge?.togglePlaybackFullScreen()
        }
    }

    func makeUIViewController(context: Context) -> Controller {
        let controller = Controller()
        controller.configuration = self
        return controller
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.configuration = self
    }

    static func dismantleUIViewController(_ controller: Controller, coordinator: ()) {
        controller.cancelPendingUpdate()
        controller.restoreTitlebar(restoringHome: true)
        controller.configuration = nil
    }
}
#endif
