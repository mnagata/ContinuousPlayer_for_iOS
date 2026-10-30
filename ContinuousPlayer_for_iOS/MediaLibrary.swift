import Foundation
import Observation

/// Owns folder access for as long as its playlist can be played.
@MainActor @Observable
final class MediaLibrary {
    let playback: PlaybackController
    private(set) var files: [URL] = []
    private(set) var folderName = ""
    private(set) var isLoading = false
    var error: String?
    private(set) var needsFolderPermission = false
    private var scopedURL: URL?
    #if targetEnvironment(macCatalyst)
    private var scopedFileURL: URL?
    #endif
    private(set) var folderURL: URL?
    private(set) var currentDirectoryURL: URL?
    private let bookmarkKey: String
    private let defaults: UserDefaults
    private let scan: (URL) async throws -> [URL]

    init(defaults: UserDefaults = .standard, playback: PlaybackController? = nil,
         scan: @escaping (URL) async throws -> [URL] = MediaScanner.scan) {
        self.playback = playback ?? PlaybackController()
        self.defaults = defaults
        self.scan = scan
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
            #if targetEnvironment(macCatalyst)
            let options: URL.BookmarkResolutionOptions = [.withoutUI, .withSecurityScope]
            #else
            let options: URL.BookmarkResolutionOptions = .withoutUI
            #endif
            let url = try URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
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
                files = try await scan(url)
                playback.setPlaylist(files)
            }
            if persist {
                #if targetEnvironment(macCatalyst)
                let options: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
                #else
                // iOS implicitly preserves the picker URL's security scope.
                let options: URL.BookmarkCreationOptions = .minimalBookmark
                #endif
                let data = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
                defaults.set(data, forKey: bookmarkKey)
            }
        } catch {
            needsFolderPermission = PlaybackController.isAccessFailure(error)
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
            _ = try await scan(directory)
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
        playback.stageSelection(selectedURL)
        let revision = playback.sessionRevision
        let interruption = playback.interruptionRevision
        files = []
        guard MediaScanner.isSupported(selectedURL) else {
            error = "このファイル形式は対象外です。対応形式: " + MediaScanner.extensions.sorted().joined(separator: ", ")
            playback.selectionFailed(error!)
            return
        }
        let accessing = selectedURL.startAccessingSecurityScopedResource()
        #if targetEnvironment(macCatalyst)
        let previousFileScope = scopedFileURL
        scopedFileURL = accessing ? selectedURL : nil
        previousFileScope?.stopAccessingSecurityScopedResource()
        #else
        defer { if accessing { selectedURL.stopAccessingSecurityScopedResource() } }
        #endif
        do {
            let parent = selectedURL.deletingLastPathComponent()
            #if !targetEnvironment(macCatalyst)
            let parentPath = parent.standardizedFileURL.resolvingSymlinksInPath().path
            guard let folderURL else { throw CocoaError(.fileReadNoPermission) }
            let allowedPath = folderURL.standardizedFileURL.resolvingSymlinksInPath().path
            guard parentPath == allowedPath || parentPath.hasPrefix(allowedPath + "/") else {
                throw CocoaError(.fileReadNoPermission)
            }
            #endif
            let sorted = try await scan(parent)
            guard !Task.isCancelled, playback.sessionRevision == revision else { return }
            guard let selected = sorted.first(where: {
                $0.standardizedFileURL.resolvingSymlinksInPath() == selectedURL.standardizedFileURL.resolvingSymlinksInPath()
            }) else {
                error = "選択したファイルは再生対象ではありません。動画・音声ファイルを選んでください。"
                playback.selectionFailed(error!)
                return
            }
            files = sorted
            currentDirectoryURL = parent.appendingPathComponent("", isDirectory: true)
            folderName = parent.lastPathComponent
            playback.setPlaylist(sorted)
            playback.commitSelection(selected, autoplay: autoplay && playback.interruptionRevision == interruption)
        } catch {
            guard !Task.isCancelled, playback.sessionRevision == revision else { return }
            needsFolderPermission = PlaybackController.isAccessFailure(error)
            #if targetEnvironment(macCatalyst)
            self.error = needsFolderPermission
                ? "同じフォルダーのファイルを連続再生するには、「\(selectedURL.deletingLastPathComponent().lastPathComponent)」フォルダーを選択してください。選択したフォルダーは次回も使用できます。"
                : "同じフォルダーのファイルを読み込めません。\(error.localizedDescription)"
            #else
            self.error = needsFolderPermission
                ? "ファイル一覧の「保存済みフォルダー」から、選択したファイルのフォルダーを登録し直してください。"
                : "同じフォルダーのファイルを読み込めません。\(error.localizedDescription)"
            #endif
            playback.selectionFailed(self.error!, accessFailure: needsFolderPermission)
        }
    }

    func stop() { playback.setPlaylist(files) }

    /// Release only the session grant; registration/bookmark persistence is separate.
    func releasePlaybackAccess() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        #if targetEnvironment(macCatalyst)
        scopedFileURL?.stopAccessingSecurityScopedResource()
        scopedFileURL = nil
        #endif
    }

    /// Replace the grant only. Reauthorization is not a playback command.
    func renewPlaybackAccess(to url: URL) {
        let acquired = url.startAccessingSecurityScopedResource()
        let previous = scopedURL
        scopedURL = acquired ? url : nil
        previous?.stopAccessingSecurityScopedResource()
    }

    func forgetFolder() {
        playback.setPlaylist([])
        files = []
        folderURL = nil
        currentDirectoryURL = nil
        folderName = ""
        error = nil
        needsFolderPermission = false
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        #if targetEnvironment(macCatalyst)
        scopedFileURL?.stopAccessingSecurityScopedResource()
        scopedFileURL = nil
        #endif
        defaults.removeObject(forKey: bookmarkKey)
    }

    isolated deinit {
        scopedURL?.stopAccessingSecurityScopedResource()
        #if targetEnvironment(macCatalyst)
        scopedFileURL?.stopAccessingSecurityScopedResource()
        #endif
    }
}
