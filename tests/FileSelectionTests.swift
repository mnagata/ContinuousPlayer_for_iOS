import Foundation
import AVFoundation

@MainActor private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
@MainActor private func wait(_ condition: @escaping () -> Bool) async {
    for _ in 0..<400 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(20))
    }
    fatalError("Timed out")
}
@MainActor private final class DelayedBrowse {
    var pending: [CheckedContinuation<[SelectionRow], Error>] = []
    func read(_ folder: SelectionFolder) async throws -> [SelectionRow] {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func complete(_ rows: [SelectionRow]) { pending.removeFirst().resume(returning: rows) }
}

@MainActor private final class DelayedLocalScan {
    var pending: [CheckedContinuation<[URL], Error>] = []
    func read(_ folder: URL) async throws -> [URL] {
        try await withCheckedThrowingContinuation { pending.append($0) }
    }
    func complete(_ files: [URL]) { pending.removeFirst().resume(returning: files) }
}

@main struct FileSelectionTests {
    @MainActor static func main() async throws {
        let suite = "continuousplayer.stage2.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let registrations = RegisteredFolders(defaults: defaults)
        let server = DLNAServer(id: "nas-A", name: "NAS", descriptionURL: URL(string: "http://127.0.0.1/description.xml")!,
                                controlURL: URL(string: "http://127.0.0.1/control")!, serviceType: "ContentDirectory")
        let ancestors = [RegisteredDLNAPath(id: "0", title: "Server"), RegisteredDLNAPath(id: "private", title: "Ancestor")]
        let rootPath = ancestors + [RegisteredDLNAPath(id: "root", title: "Root")]
        let root = SelectionFolder.dlna(server: server, root: rootPath, path: rootPath, adding: false)
        let stream = URL(string: "http://127.0.0.1/shared.mp4")!
        let remoteA = DLNAEntry(id: "a", title: "OP", isContainer: false, resourceURL: stream, size: 1)
        let remoteB = DLNAEntry(id: "b", title: "ED", isContainer: false, resourceURL: stream, size: 1)
        let a = SelectionRow(id: "nas-A|a", name: "OP", isFolder: false, url: stream, remote: remoteA)
        let b = SelectionRow(id: "nas-A|b", name: "ED", isFolder: false, url: stream, remote: remoteB)
        let childEntry = DLNAEntry(id: "child", title: "Child", isContainer: true, resourceURL: nil, size: nil)
        let child = SelectionRow(id: "nas-A|child", name: "Child", isFolder: true, url: nil, remote: childEntry)
        expect(registrations.local.isEmpty && registrations.dlna.isEmpty, "starts empty")
        let saved = registrations.addDLNA(server: server, path: rootPath)
        _ = registrations.addDLNA(server: server, path: rootPath)
        expect(registrations.dlna.count == 1, "registering twice must update, never remove")
        expect(root.parent == nil, "registration root cannot expose ancestors")
        let relocated = DLNAServer(id: server.id, name: "Renamed NAS", descriptionURL: URL(string: "http://127.0.0.2/description.xml")!,
                                   controlURL: URL(string: "http://127.0.0.2/control")!, serviceType: server.serviceType)
        expect(root.identity == SelectionFolder.dlna(server: relocated, root: rootPath, path: rootPath, adding: false).identity,
               "selection memory uses server/object identity across address and name updates")
        let extra = registrations.addDLNA(server: server, path: [RegisteredDLNAPath(id: "extra", title: "AAA first")])
        var chosen: MediaSelection?
        var cancellations = 0
        let flow = FileSelectionCoordinator(origin: .playback, registrations: registrations,
            browse: { folder in folder.title == "Child" ? [a,b] : [child,a,b] },
            reconnect: { _ in server }, choose: { chosen = $0 }, cancelled: { cancellations += 1 })
        flow.openCurrent(root, rowID: b.id)
        await wait { !flow.isLoading }
        expect(flow.selectedRowID == b.id, "shared URLs retain distinct server/object row identity")
        flow.activate(child)
        await wait { !flow.isLoading }
        expect(flow.title == "Child", "child opened")
        flow.back()
        expect(flow.title == "Root" && flow.selectedRowID == child.id, "parent restores child selection")
        flow.back()
        expect(flow.page == .saved && flow.title == "保存済みフォルダー", "root back goes to saved, not server ancestors or cancellation")
        expect(cancellations == 0, "parent movement is not cancellation")
        expect(flow.selectedSavedID == "saved.dlna.\(saved.id)", "return from current root selects its registration, not the first row")
        flow.open(saved)
        await wait { !flow.isLoading }
        flow.activate(b)
        expect(chosen?.selected.id == b.id && flow.isClosed, "commit exact object ID and finish flow")
        registrations.removeDLNA(extra)
        print("PASS: registration upsert; bounded DLNA root; parent selection; shared-URL object identity")

        let nestedPath = rootPath + [RegisteredDLNAPath(id: childEntry.id, title: childEntry.title)]
        let nested = SelectionFolder.dlna(server: server, root: rootPath, path: nestedPath, adding: false)
        let returning = FileSelectionCoordinator(origin: .playback, registrations: registrations,
            browse: { folder in folder.identity == root.identity ? [a, child, b] : [a, b] },
            choose: { _ in }, cancelled: {})
        returning.openCurrent(nested, rowID: b.id)
        await wait { !returning.isLoading }
        let revision = returning.focusRevision
        returning.back()
        await wait { !returning.isLoading }
        expect(returning.page == .folder(root) && returning.selectedRowID == child.id,
               "back from playback selects the departed DLNA directory without parent history")
        expect(returning.focusRevision > revision, "return requests scrolling to the directory selection")
        returning.openCurrent(root, rowID: b.id)
        returning.openCurrent(nested, rowID: a.id)
        await wait { !returning.isLoading }
        returning.back()
        expect(returning.selectedRowID == child.id, "cached parent also selects the departed directory")
        returning.finish()
        let removedDirectory = FileSelectionCoordinator(origin: .playback, registrations: registrations,
            browse: { _ in [a, b] }, choose: { _ in }, cancelled: {})
        removedDirectory.openCurrent(nested, rowID: b.id)
        await wait { !removedDirectory.isLoading }
        removedDirectory.back()
        await wait { !removedDirectory.isLoading }
        expect(removedDirectory.selectedRowID == a.id, "missing departed directory falls back to an existing row")
        removedDirectory.finish()
        print("PASS: playback directory return selects and reveals its DLNA parent row, with and without cache")

        let second = registrations.addDLNA(server: server, path: [RegisteredDLNAPath(id: "second", title: "ZZ Second")])
        let removal = FileSelectionCoordinator(origin: .home, registrations: registrations, browse: { _ in throw DLNAError.message("offline") }, choose: { _ in }, cancelled: {})
        removal.removeDLNA(saved)
        expect(removal.selectedSavedID == "saved.dlna.\(second.id)", "removal focuses next row")
        let third = registrations.addDLNA(server: server, path: [RegisteredDLNAPath(id: "third", title: "ZZZ Third")])
        removal.removeDLNA(third)
        expect(removal.selectedSavedID == "saved.dlna.\(second.id)", "last removal focuses previous row")
        removal.removeDLNA(second)
        expect(removal.selectedSavedID == "saved.addFolder", "empty removal focuses add")
        removal.showSources(); removal.showServers(); removal.openServer(server)
        await wait { !removal.isLoading }
        // No real HTTP fixture here; an error must not remove a registration.
        expect(registrations.dlna.isEmpty, "network errors never create/remove registrations")
        print("PASS: removal next/previous/add focus and offline persistence separation")

        let delayed = DelayedBrowse()
        let busyRegistration = registrations.addDLNA(server: server, path: rootPath)
        var cancelledLoad = false
        let loading = FileSelectionCoordinator(origin: .playback, registrations: registrations,
            browse: { try await delayed.read($0) }, choose: { _ in fatalError("old row activated") }, cancelled: { cancelledLoad = true })
        loading.openCurrent(root, rowID: a.id)
        await wait { delayed.pending.count == 1 }
        delayed.complete([child,a,b]); await wait { !loading.isLoading }
        loading.reload(); await wait { delayed.pending.count == 1 }
        expect(loading.rows == [child,a,b] && loading.title == "Root", "reload retains rows/title")
        expect(!loading.showsLoading, "spinner is delayed")
        loading.activate(a); loading.registerCurrent(); loading.showSources()
        loading.removeDLNA(busyRegistration)
        expect(registrations.dlna.count == 1, "busy blocks removal even from native pointer callbacks")
        expect(loading.isLoading && loading.title == "Root", "busy blocks stale row/add/register")
        try? await Task.sleep(for: .milliseconds(650))
        expect(loading.showsLoading, "spinner overlays after half a second")
        let token = loading.requestRevision
        loading.back()
        expect(loading.isClosed && cancelledLoad && loading.requestRevision > token, "back while fetching cancels entire flow")
        delayed.complete([b]); try? await Task.sleep(for: .milliseconds(80))
        expect(loading.rows == [child,a,b] && loading.isClosed && !loading.showsLoading, "uncancellable late result discarded")
        registrations.removeDLNA(busyRegistration)
        print("PASS: retained reload, delayed overlay, busy isolation and late-result invalidation")

        let localRoot = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "validation/common-spec/media", isDirectory: true).standardizedFileURL
        let local = try registrations.addLocal(localRoot)
        let same = try registrations.addLocal(localRoot)
        expect(local.id == same.id && registrations.local.count == 1, "duplicate local registration updates identity")
        let sourceFlow = FileSelectionCoordinator(origin: .home, registrations: registrations, choose: { _ in }, cancelled: {})
        sourceFlow.showSources(); sourceFlow.registerLocal(localRoot)
        expect(sourceFlow.page == .saved && sourceFlow.selectedSavedID == "saved.local.\(local.id)", "local registration returns selected row")
        sourceFlow.showSources(); sourceFlow.cancelPage()
        expect(sourceFlow.page == .saved && !sourceFlow.isClosed, "whole add cancel returns saved list")
        sourceFlow.showSources(); sourceFlow.back()
        expect(sourceFlow.page == .saved && !sourceFlow.isClosed, "add Back returns saved list")
        let localFolder = SelectionFolder.local(root: localRoot, directory: localRoot)
        expect(localFolder.parent == nil, "local root bounded")
        let localChildURL = localRoot.appendingPathComponent("Other Folder", isDirectory: true)
        let localChild = SelectionRow(id: localChildURL.standardizedFileURL.path, name: "Other Folder", isFolder: true,
                                     url: localChildURL, remote: nil)
        let localReturning = FileSelectionCoordinator(origin: .playback, registrations: registrations,
            browse: { folder in folder.identity == localFolder.identity ? [a, localChild, b] : [a, b] },
            choose: { _ in }, cancelled: {})
        localReturning.openCurrent(.local(root: localRoot, directory: localChildURL), rowID: b.id)
        await wait { !localReturning.isLoading }
        localReturning.back()
        await wait { !localReturning.isLoading }
        expect(localReturning.page == .folder(localFolder) && localReturning.selectedRowID == localChild.id,
               "back from playback selects the departed local directory without parent history")
        localReturning.back()
        expect(localReturning.selectedSavedID == "saved.local.\(local.id)", "local root return selects its registration")
        localReturning.finish()
        let localRows = try await FileSelectionCoordinator.readFolder(localFolder)
        expect(localRows.contains { $0.isFolder } && localRows.contains { !$0.isFolder }, "real local coordinated browse")
        print("PASS: local duplicate/update, selected registration, add cancellation and coordinated browse")

        let scene = PlayerSceneModel(registrations: registrations, defaults: defaults)
        let file = localRoot.appendingPathComponent("Fixture OP.mp4")
        let row = localRows.first { $0.url?.standardizedFileURL == file }!
        scene.commit(MediaSelection(folder: localFolder, rows: localRows, selected: row, access: BrowsingFolderAccess(localRoot)))
        expect(scene.showsPlayer && scene.isPreparingSelection, "black player is installed synchronously before scanning")
        scene.openSelection()
        expect(scene.selection == nil, "pending parent enumeration cannot race a second modal")
        await wait { !scene.library.isLoading && scene.playback.player.currentItem?.status == .readyToPlay }
        await withCheckedContinuation { done in
            scene.playback.player.seek(to: CMTime(seconds: 30, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero) { _ in done.resume() }
        }
        let item = scene.playback.player.currentItem
        scene.openSelection()
        await wait { scene.selection?.isLoading == false }
        let active = scene.selection!
        active.back()
        expect(active.page == .saved && scene.playback.isPresenting, "saved list remains inside original presentation")
        active.removeLocal(local)
        active.showSources()
        active.registerLocal(localRoot.appendingPathComponent("Other Folder", isDirectory: true))
        expect(scene.playback.player.currentItem === item, "registration/remove do not reset active item/grant")
        active.cancel()
        expect(scene.playback.state.wantsToPlay && scene.playback.player.currentItem === item, "cancel after add/remove restores original playing intent")
        expect(abs(scene.playback.player.currentTime().seconds - 30) < 1, "position preserved across registration mutation")
        expect(FileManager.default.fileExists(atPath: file.path), "unregister never deletes media")
        scene.openSelection(); await wait { scene.selection?.isLoading == false }
        scene.session.setBlocked("test-interruption", true); scene.session.setBlocked("test-interruption", false)
        scene.selection!.cancel()
        expect(!scene.playback.state.wantsToPlay, "interruption still wins after common selection")
        scene.openSelection(); scene.home()
        scene.commit(MediaSelection(folder: localFolder, rows: localRows, selected: row, access: BrowsingFolderAccess(localRoot)))
        scene.home()
        try? await Task.sleep(for: .milliseconds(100))
        expect(scene.selection == nil && !scene.showsPlayer && scene.playback.player.currentItem == nil, "home closes selection and pending work")
        print("PASS: active local registration removal/addition retains item, 30-second position and grant; interruption and home")
        let delayedScan = DelayedLocalScan()
        let chained = PlayerSceneModel(registrations: registrations, defaults: defaults, localScan: { try await delayedScan.read($0) })
        chained.commit(MediaSelection(folder: localFolder, rows: localRows, selected: row, access: BrowsingFolderAccess(localRoot)))
        await wait { delayedScan.pending.count == 1 }
        chained.home()
        let ed = localRows.first { $0.url?.lastPathComponent == "Fixture ED.mp4" }!
        chained.commit(MediaSelection(folder: localFolder, rows: localRows, selected: ed, access: BrowsingFolderAccess(localRoot)))
        try? await Task.sleep(for: .milliseconds(80))
        expect(delayedScan.pending.count == 1 && chained.isPreparingSelection, "new choice waits for uncancellable old scan cleanup")
        delayedScan.complete([file, ed.url!])
        await wait { delayedScan.pending.count == 1 }
        expect(chained.playback.state.currentURL == ed.url && chained.isPreparingSelection, "late old result cannot replace new choice")
        delayedScan.complete([file, ed.url!])
        await wait { !chained.isPreparingSelection && chained.playback.player.currentItem?.status == .readyToPlay }
        expect(chained.playback.state.currentURL == ed.url && chained.playback.state.wantsToPlay, "new local choice must prepare after old cancellation")
        chained.home()
        print("PASS: pending scan blocks modal races; home then new selection waits for provider cleanup without losing the new choice")
        print("Stage 2 file selection tests passed")
    }
}
