import Foundation
import Observation

/// Owns folder access for as long as its playlist can be played.
@MainActor @Observable
final class MediaLibrary {
    let playback = PlaybackController()
    private(set) var files: [URL] = []
    private(set) var folderName = ""
    private(set) var isLoading = false
    var error: String?
    private(set) var needsFolderPermission = false
    private var scopedURL: URL?
    private(set) var folderURL: URL?
    private(set) var currentDirectoryURL: URL?
    private let bookmarkKey: String
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        bookmarkKey = ProcessInfo.processInfo.arguments.contains("--ui-bookmark-tests")
            ? "uitests.folder.bookmark" : "validation.folder.bookmark"
        #else
        bookmarkKey = "validation.folder.bookmark"
        #endif
    }
    var hasSavedFolder: Bool { defaults.data(forKey: bookmarkKey) != nil }

    func restore(loadPlaylist: Bool = true) async {
        guard let data = defaults.data(forKey: bookmarkKey) else { return }
        playback.setPlaylist([])
        files = []
        error = nil
        needsFolderPermission = false
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale)
            await open(url, loadPlaylist: loadPlaylist)
        } catch {
            self.error = "保存したフォルダーを開けません。フォルダーを選び直してください。"
        }
    }

    func open(_ url: URL, persist: Bool = true, loadPlaylist: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        playback.setPlaylist([])
        files = []
        error = nil
        needsFolderPermission = false
        let previousScope = scopedURL
        scopedURL = url.startAccessingSecurityScopedResource() ? url : nil
        previousScope?.stopAccessingSecurityScopedResource()
        folderURL = url
        currentDirectoryURL = url.appendingPathComponent("", isDirectory: true)
        folderName = url.lastPathComponent
        do {
            if loadPlaylist {
                files = try await MediaScanner.scan(url)
                playback.setPlaylist(files)
            }
            if persist {
                // iOS implicitly preserves the picker URL's security scope in its bookmark.
                // .withSecurityScope is a macOS-only option and is unavailable on iOS.
                let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                defaults.set(data, forKey: bookmarkKey)
            }
        } catch {
            self.error = "フォルダーの読み込みに失敗しました。\(error.localizedDescription)"
        }
    }

    /// Persist permission only: do not enumerate or start playback from this action.
    func authorizeFolder(_ url: URL) async {
        await open(url, loadPlaylist: false)
    }

    /// Validate the current directory without resetting it to the permission root.
    func prepareFileSelection() async -> Bool {
        guard !isLoading else { return false }
        if folderURL == nil, hasSavedFolder {
            await restore(loadPlaylist: false)
            guard error == nil else { return false }
        }
        guard let directory = currentDirectoryURL else { return false }
        isLoading = true
        defer { isLoading = false }
        error = nil
        needsFolderPermission = false
        do {
            _ = try await MediaScanner.scan(directory)
            return true
        } catch {
            self.error = "現在のフォルダーを読み込めません。USBストレージの接続とアクセス許可を確認してください。"
            needsFolderPermission = PlaybackController.isAccessFailure(error)
            return false
        }
    }

    func playFolder(_ url: URL, persist: Bool = true) async {
        await open(url, persist: persist)
        guard error == nil else { return }
        guard let first = files.first else {
            error = "対象ファイルがありません。動画・音声ファイルのあるフォルダーを選んでください。"
            return
        }
        playback.select(first, autoplay: true)
    }

    /// Keep the folder grant alive while scanning the selected file's parent.
    func playFromSelection(_ selectedURL: URL, autoplay: Bool = true) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        error = nil
        needsFolderPermission = false
        playback.setPlaylist([])
        files = []
        guard MediaScanner.isSupported(selectedURL) else {
            error = "このファイル形式は対象外です。対応形式: " + MediaScanner.extensions.sorted().joined(separator: ", ")
            return
        }
        let accessing = selectedURL.startAccessingSecurityScopedResource()
        defer { if accessing { selectedURL.stopAccessingSecurityScopedResource() } }
        do {
            let parent = selectedURL.deletingLastPathComponent()
            let parentPath = parent.standardizedFileURL.resolvingSymlinksInPath().path
            guard let folderURL else { throw CocoaError(.fileReadNoPermission) }
            let allowedPath = folderURL.standardizedFileURL.resolvingSymlinksInPath().path
            guard parentPath == allowedPath || parentPath.hasPrefix(allowedPath + "/") else {
                throw CocoaError(.fileReadNoPermission)
            }
            let sorted = try await MediaScanner.scan(parent)
            guard let selected = sorted.first(where: {
                $0.standardizedFileURL.resolvingSymlinksInPath() == selectedURL.standardizedFileURL.resolvingSymlinksInPath()
            }) else {
                error = "選択したファイルは再生対象ではありません。動画・音声ファイルを選んでください。"
                return
            }
            files = sorted
            currentDirectoryURL = parent.appendingPathComponent("", isDirectory: true)
            folderName = parent.lastPathComponent
            playback.setPlaylist(sorted)
            playback.select(selected, autoplay: autoplay)
        } catch {
            needsFolderPermission = PlaybackController.isAccessFailure(error)
            self.error = needsFolderPermission
                ? "ホームの「USBストレージへのアクセスを許可」で、選択したファイルのフォルダーを許可してください。"
                : "同じフォルダーのファイルを読み込めません。\(error.localizedDescription)"
        }
    }

    func stop() { playback.setPlaylist(files) }

    isolated deinit { scopedURL?.stopAccessingSecurityScopedResource() }
}
