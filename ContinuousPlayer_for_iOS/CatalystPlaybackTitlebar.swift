#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// Owns the native title and toolbar only for the lifetime of this window's player.
struct CatalystPlaybackTitlebar: UIViewControllerRepresentable {
    let filename: String
    let isPlaying: Bool
    let actionsEnabled: Bool
    let playbackEnabled: Bool
    let home: () -> Void
    let chooseFolder: () -> Void
    let showInfo: () -> Void
    let togglePlayback: () -> Void

    final class Controller: UIViewController, NSToolbarDelegate {
        var configuration: CatalystPlaybackTitlebar? {
            didSet { updateTitlebar() }
        }

        private static let homeID = NSToolbarItem.Identifier("playback.home")
        private static let folderID = NSToolbarItem.Identifier("playback.folder")
        private static let infoID = NSToolbarItem.Identifier("playback.info")
        private static let playID = NSToolbarItem.Identifier("playback.playPause")
        private weak var scene: UIWindowScene?
        private var previousTitle = "ContinuousPlayer"
        private var appliedTitle: String?
        private var previousToolbar: NSToolbar?
        private var previousStyle: UITitlebarToolbarStyle = .automatic
        private var previousAutoHide = false

        private lazy var playbackToolbar: NSToolbar = {
            let toolbar = NSToolbar(identifier: "ContinuousPlayer.Playback")
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
                playbackToolbar.isVisible = true
            }

            let name = configuration.filename as NSString
            let displayName = MediaScanner.extensions.contains(name.pathExtension.lowercased())
                ? name.deletingPathExtension : configuration.filename
            let title = displayName.isEmpty ? "ContinuousPlayer" : displayName
            windowScene.title = title
            appliedTitle = title
            for item in playbackToolbar.items { configure(item) }
        }

        func restoreTitlebar() {
            if let scene {
                if scene.title == appliedTitle { scene.title = previousTitle }
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
            [Self.homeID, .flexibleSpace, Self.folderID, Self.infoID, Self.playID]
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            toolbarDefaultItemIdentifiers(toolbar)
        }

        func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier identifier: NSToolbarItem.Identifier,
                     willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
            guard [Self.homeID, Self.folderID, Self.infoID, Self.playID].contains(identifier) else { return nil }
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
                label = "OP / EDを選び直す"
                symbol = "folder"
                item.action = #selector(browseFiles)
            case Self.infoID:
                label = "メディア情報"
                symbol = "info.circle"
                item.action = #selector(showInfo)
            case Self.playID:
                label = configuration.isPlaying ? "一時停止" : "再生"
                symbol = configuration.isPlaying ? "pause.fill" : "play.fill"
                item.action = #selector(togglePlayback)
            default:
                return
            }
            item.label = label
            item.paletteLabel = label
            item.toolTip = label
            item.image = UIImage(systemName: symbol)
            item.isEnabled = configuration.actionsEnabled
                && (item.itemIdentifier != Self.playID || configuration.playbackEnabled)
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

        @objc private func togglePlayback() {
            guard let configuration, configuration.actionsEnabled, configuration.playbackEnabled else { return }
            configuration.togglePlayback()
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
        controller.restoreTitlebar()
        controller.configuration = nil
    }
}
#endif
