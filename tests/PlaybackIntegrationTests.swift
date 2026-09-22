import AVFoundation
import Foundation

@main struct PlaybackIntegrationTests {
    @MainActor static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(8)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        precondition(condition(), "Timed out")
    }

    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let files = ["a.wav", "b.wav"].map { directory.appendingPathComponent($0) }
        let playlistFolder = directory.appendingPathComponent("playlist", isDirectory: true)
        try FileManager.default.createDirectory(at: playlistFolder, withIntermediateDirectories: true)
        for name in ["Series ED2.wav", "Series OP2.wav", "Series ED.wav", "Series OP.wav"] {
            try FileManager.default.copyItem(at: files[0], to: playlistFolder.appendingPathComponent(name))
        }
        let suiteName = "bookmark-tests-" + UUID().uuidString
        let isolatedDefaults = UserDefaults(suiteName: suiteName)!
        defer { isolatedDefaults.removePersistentDomain(forName: suiteName) }
        let authorizedLibrary = MediaLibrary(defaults: isolatedDefaults)
        await authorizedLibrary.authorizeFolder(playlistFolder)
        precondition(authorizedLibrary.hasSavedFolder && authorizedLibrary.error == nil)
        precondition(authorizedLibrary.files.isEmpty && authorizedLibrary.playback.player.currentItem == nil,
                     "Authorization must not create a playlist or play")
        let restoredLibrary = MediaLibrary(defaults: isolatedDefaults)
        await restoredLibrary.restore(loadPlaylist: false)
        precondition(restoredLibrary.error == nil && restoredLibrary.folderURL != nil)
        precondition(restoredLibrary.files.isEmpty && restoredLibrary.playback.player.currentItem == nil)
        await restoredLibrary.playFromSelection(playlistFolder.appendingPathComponent("Series ED.wav"))
        precondition(restoredLibrary.error == nil && restoredLibrary.playback.currentName == "Series ED.wav")
        restoredLibrary.stop()
        await restoredLibrary.playFromSelection(playlistFolder.appendingPathComponent("Series OP.wav"), autoplay: false)
        try await waitUntil { !restoredLibrary.playback.isLoading }
        precondition(!restoredLibrary.playback.state.wantsToPlay && restoredLibrary.playback.player.rate == 0,
                     "File selection must support preparing without playback during presentation")
        restoredLibrary.playback.resume()
        try await waitUntil { restoredLibrary.playback.player.currentTime().seconds > 0 }
        restoredLibrary.stop()
        isolatedDefaults.set(Data([0, 1, 2]), forKey: "validation.folder.bookmark")
        let invalidLibrary = MediaLibrary(defaults: isolatedDefaults)
        await invalidLibrary.restore(loadPlaylist: false)
        precondition(invalidLibrary.error != nil && invalidLibrary.playback.player.currentItem == nil)
        print("PASS: authorization-only bookmark save, new-instance restoration, selection and invalid bookmark")
        let library = MediaLibrary()
        let unsupported = playlistFolder.appendingPathComponent("notes.txt")
        try Data("not media".utf8).write(to: unsupported)
        await library.playFromSelection(unsupported)
        precondition(library.error?.contains("対象外") == true)
        precondition(!library.needsFolderPermission && library.playback.player.currentItem == nil)
        let selected = playlistFolder.appendingPathComponent("Series ED.wav")
        await library.playFromSelection(selected)
        precondition(library.needsFolderPermission && library.files.isEmpty)
        precondition(library.playback.player.currentItem == nil)
        await library.open(directory, persist: false, loadPlaylist: false)
        precondition(library.files.isEmpty, "Permission alone must not build a playlist")
        let canSelectFile = await library.prepareFileSelection()
        precondition(canSelectFile, "A readable current folder allows file selection")
        await library.playFromSelection(selected)
        precondition(library.error == nil && !library.needsFolderPermission)
        precondition(library.files.map(\.lastPathComponent) == ["Series OP.wav", "Series ED.wav", "Series OP2.wav", "Series ED2.wav"])
        precondition(library.playback.state.currentURL?.standardizedFileURL.resolvingSymlinksInPath() == selected.standardizedFileURL.resolvingSymlinksInPath(), "Start at the selected file after sorting")
        library.playback.pause()
        library.stop()
        let reopenCurrentDirectory = await library.prepareFileSelection()
        precondition(reopenCurrentDirectory)
        precondition(library.currentDirectoryURL?.standardizedFileURL.resolvingSymlinksInPath() == playlistFolder.standardizedFileURL.resolvingSymlinksInPath())
        precondition(library.currentDirectoryURL?.hasDirectoryPath == true)
        precondition(library.folderURL?.standardizedFileURL.resolvingSymlinksInPath() == directory.standardizedFileURL.resolvingSymlinksInPath(), "Keep the permission root separate")
        print("PASS: reopening after stop keeps the playing subdirectory and its directory URL hint")
        await library.playFromSelection(directory.deletingLastPathComponent().appendingPathComponent("outside.wav"))
        precondition(library.error != nil && library.needsFolderPermission && library.files.isEmpty)
        precondition(library.playback.player.currentItem == nil)
        await library.playFolder(playlistFolder, persist: false)
        precondition(library.error == nil)
        precondition(library.playback.state.currentURL?.lastPathComponent == "Series OP.wav")
        precondition(library.playback.state.wantsToPlay)
        library.playback.pause()
        library.stop()
        let secondFolder = directory.appendingPathComponent("second-playlist")
        try FileManager.default.createDirectory(at: secondFolder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: files[0], to: secondFolder.appendingPathComponent("Other OP.wav"))
        await library.playFolder(secondFolder, persist: false)
        precondition(library.error == nil && library.playback.state.wantsToPlay)
        precondition(library.playback.currentName == "Other OP.wav")
        try await waitUntil { library.playback.player.currentTime().seconds > 0 }
        library.playback.pause()
        let emptyFolder = directory.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: emptyFolder, withIntermediateDirectories: true)
        await library.playFolder(emptyFolder, persist: false)
        precondition(library.error != nil && library.playback.player.currentItem == nil)
        await library.playFolder(directory.appendingPathComponent("missing"), persist: false)
        precondition(library.error != nil && library.playback.player.currentItem == nil)
        let canSelectMissing = await library.prepareFileSelection()
        precondition(!canSelectMissing, "An unreadable current folder must request folder selection")
        await library.playFolder(playlistFolder, persist: false)
        precondition(library.error == nil && !library.needsFolderPermission)
        precondition(library.playback.currentName == "Series OP.wav")
        try await waitUntil { library.playback.player.currentTime().seconds > 0 }
        library.playback.pause()
        // Selecting outside the current grant must recover after granting its folder.
        await library.playFromSelection(secondFolder.appendingPathComponent("Other OP.wav"))
        precondition(library.needsFolderPermission)
        await library.playFolder(secondFolder, persist: false)
        precondition(library.error == nil && !library.needsFolderPermission)
        precondition(library.playback.currentName == "Other OP.wav")
        try await waitUntil { library.playback.player.currentTime().seconds > 0 }
        library.playback.pause()
        print("PASS: folder selection starts sorted first item; empty and missing folders do not play")
        print("PASS: file selection, parent-folder sorting, selected start and outside-folder rejection")

        let preparing = PlaybackController()
        preparing.setPlaylist(files)
        preparing.select(files[0], autoplay: true)
        precondition(preparing.isLoading && preparing.player.rate == 0,
                     "Playback clock must not start before metadata and preroll finish")
        preparing.pause()
        try await waitUntil { !preparing.isLoading }
        precondition(preparing.player.rate == 0 && !preparing.state.wantsToPlay,
                     "Pausing during preparation must prevent automatic playback")
        precondition(preparing.mediaInfo.name == "a.wav" && preparing.mediaInfo.audio != "取得できません")
        preparing.resume()
        try await waitUntil { preparing.player.currentTime().seconds > 0 }
        preparing.select(files[0], autoplay: true)
        preparing.select(files[1], autoplay: false)
        try await waitUntil { !preparing.isLoading }
        precondition(preparing.mediaInfo.name == "b.wav" && preparing.player.rate == 0,
                     "An obsolete preparation must not publish metadata or start a replacement item")
        preparing.select(files[0], autoplay: true)
        preparing.setPlaylist([])
        try await Task.sleep(for: .milliseconds(100))
        precondition(preparing.player.currentItem == nil && !preparing.isLoading && preparing.mediaInfo.name.isEmpty)
        print("PASS: startup preparation, pause, replacement and cancellation")

        let controller = PlaybackController()
        controller.setPlaylist(files)
        controller.select(files[0])
        try await waitUntil { controller.state.ended }
        precondition(controller.state.currentURL == files[1] && !controller.state.wantsToPlay)

        controller.select(files[0])
        controller.pause()
        let oldItem = controller.player.currentItem!
        controller.move(1)
        try await waitUntil { !controller.isLoading && controller.player.currentItem?.status == .readyToPlay }
        precondition(!controller.state.wantsToPlay && controller.player.rate == 0)
        NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: oldItem)
        try await Task.sleep(for: .milliseconds(100))
        precondition(controller.state.currentURL == files[1] && !controller.state.ended)
        controller.seek(by: 10)
        precondition(controller.state.currentURL == files[1] && !controller.state.ended)
        controller.select(files[0])
        precondition(!controller.state.wantsToPlay)
        try await waitUntil { !controller.isLoading && controller.player.currentItem?.status == .readyToPlay }
        controller.seek(by: -10)
        controller.seek(by: 10)
        precondition(controller.state.currentURL == files[1] && !controller.state.wantsToPlay)

        controller.setActive(false)
        controller.resume()
        controller.select(files[0], autoplay: true)
        precondition(!controller.state.wantsToPlay && controller.player.rate == 0)
        controller.setActive(true)
        precondition(!controller.state.wantsToPlay)
        controller.resume()
        controller.setInterrupted(true)
        controller.resume()
        precondition(!controller.state.wantsToPlay && controller.player.rate == 0)
        controller.move(1)
        controller.setInterrupted(false)
        precondition(!controller.state.wantsToPlay && controller.showsPauseControls)
        controller.resume()
        controller.outputDisconnected()
        precondition(!controller.state.wantsToPlay && controller.pauseReason != nil)

        let denied = NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoPermissionError)
        precondition(PlaybackController.isAccessFailure(NSError(domain: "wrapper", code: 0, userInfo: [NSUnderlyingErrorKey: denied])))
        precondition(!PlaybackController.isAccessFailure(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)))
        let failedItem = controller.player.currentItem!
        NotificationCenter.default.post(name: AVPlayerItem.failedToPlayToEndTimeNotification, object: failedItem,
            userInfo: [AVPlayerItemFailedToPlayToEndTimeErrorKey: denied])
        try await waitUntil { controller.needsFolderSelection }
        controller.resume()
        controller.select(files[0])
        controller.move(-1)
        precondition(controller.player.currentItem == nil && !controller.state.wantsToPlay)
        precondition(controller.state.currentURL == files[1])
        controller.setPlaylist(files)
        precondition(!controller.needsFolderSelection)
        controller.select(files[0], autoplay: false)
        try await waitUntil { !controller.isLoading }
        controller.checkStall(elapsed: .seconds(31))
        precondition(controller.state.consecutiveFailures == 0 && !controller.isBuffering)
        controller.resume()
        controller.checkStall(elapsed: .seconds(3))
        precondition(controller.isBuffering && !controller.showsPauseControls)
        controller.checkStall(elapsed: .seconds(31))
        precondition(controller.state.currentURL == files[1] && controller.state.consecutiveFailures == 1)
        controller.pause()
        precondition(!controller.isBuffering && controller.showsPauseControls)

        let missing = (0..<4).map { directory.appendingPathComponent("missing\($0).mp4") }
        controller.setPlaylist(missing)
        controller.select(missing[0])
        try await waitUntil { controller.state.consecutiveFailures == 3 }
        precondition(controller.state.currentURL == missing[2])
        precondition(!controller.state.wantsToPlay && controller.player.currentItem == nil && controller.error != nil)
        controller.setPlaylist(files)
        controller.select(files[0])
        controller.setPlaylist([])
        try await Task.sleep(for: .milliseconds(100))
        precondition(controller.player.currentItem == nil && controller.state.currentURL == nil)
        if CommandLine.arguments.count > 2 {
            let video = URL(fileURLWithPath: CommandLine.arguments[2])
            controller.setPlaylist([video])
            controller.select(video, autoplay: false)
            try await waitUntil { !controller.isLoading }
            precondition(controller.player.currentItem?.status == .readyToPlay && controller.player.rate == 0)
            precondition(controller.mediaInfo.video.contains("fps"), "Video metadata must be ready before playback")
            controller.resume()
            try await waitUntil { controller.player.currentTime().seconds > 0.1 }
            controller.pause()
            print("PASS: video metadata, preroll and playback")
        }
        print("Playback AVFoundation integration tests passed")
    }
}
