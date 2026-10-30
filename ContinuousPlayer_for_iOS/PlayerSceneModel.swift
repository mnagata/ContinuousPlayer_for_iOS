import Foundation
import Observation

/// The player stays mounted while the independent selection flow comes and goes.
@MainActor @Observable
final class PlayerSceneModel {
    let session = PlaybackSessionCoordinator()
    let registrations: RegisteredFolders
    #if !os(tvOS)
    let library: MediaLibrary
    var showsFixturePlaylist = false
    #endif
    var selection: FileSelectionCoordinator?
    private(set) var showsPlayer = false
    private(set) var isPreparingSelection = false
    private(set) var folderName = ""
    private(set) var source: SelectionFolder?
    private var playbackRows: [SelectionRow] = []
    private var chosenRow: SelectionRow?
    private var lastSavedID: String?
    private var snapshot: PlaybackController.PresentationSnapshot?
    @ObservationIgnored private var preparation: Task<Void, Never>?
    private var preparationRevision = 0
    var playback: PlaybackController { session.playback }

    init(registrations: RegisteredFolders? = nil, defaults: UserDefaults = .standard,
         localScan: ((URL) async throws -> [URL])? = nil) {
        self.registrations = registrations ?? RegisteredFolders(defaults: defaults)
        #if !os(tvOS)
        library = MediaLibrary(defaults: defaults, playback: session.playback, scan: localScan ?? MediaScanner.scan)
        #endif
    }
    func openSelection() {
        guard selection == nil, !playback.isPresenting, !isPreparingSelection else { return }
        if showsPlayer { snapshot = playback.beginPresentation() }
        let flow = FileSelectionCoordinator(origin: showsPlayer ? .playback : .home, registrations: registrations,
                                           choose: { [weak self] in self?.commit($0) },
                                           cancelled: { [weak self] in self?.closeSelection() })
        flow.selectedSavedID = lastSavedID
        selection = flow
        if showsPlayer, let source {
            let current = chosenRow?.url == playback.state.currentURL ? chosenRow : playbackRows.first { $0.url == playback.state.currentURL }
            flow.openCurrent(source, rowID: current?.id)
        }
    }
    func closeSelection() {
        lastSavedID = selection?.selectedSavedID ?? lastSavedID
        selection?.finish(); selection = nil
        if let snapshot { playback.endPresentation(snapshot) }
        snapshot = nil
    }
    func retryPlayback() {
        guard playback.canRetry, playback.failure != nil else { return }
        #if !os(tvOS)
        if case .local(let root, _) = source {
            let resolved = registrations.local.compactMap { try? registrations.resolve($0) }
                .first { $0.standardizedFileURL == root.standardizedFileURL } ?? root
            if library.error != nil, playback.failure?.seconds == 0, let chosenRow, let source {
                // Initial enumeration failed before a queue existed. Repeat that
                // enumeration only after the user's explicit retry.
                commit(MediaSelection(folder: source, rows: playbackRows, selected: chosenRow,
                                      access: BrowsingFolderAccess(resolved)))
                return
            }
            library.renewPlaybackAccess(to: resolved)
        }
        #endif
        playback.retry()
    }
    func home() {
        preparationRevision += 1; preparation?.cancel()
        selection?.finish(); selection = nil; snapshot = nil
        session.end(); showsPlayer = false; isPreparingSelection = false; source = nil; playbackRows = []; chosenRow = nil
        #if !os(tvOS)
        library.releasePlaybackAccess()
        showsFixturePlaylist = false
        #endif
    }
    func commit(_ choice: MediaSelection) {
        preparationRevision += 1
        let previousPreparation = preparation
        previousPreparation?.cancel()
        let token = preparationRevision
        let interruption = playback.interruptionRevision
        lastSavedID = selection?.selectedSavedID ?? lastSavedID
        selection?.finish(); selection = nil; snapshot = nil
        playback.stopSession()
        isPreparingSelection = false
        showsPlayer = true
        source = choice.folder; folderName = choice.folder.title
        playbackRows = choice.rows; chosenRow = choice.selected
        switch choice.folder {
        case .local(let root, _):
            #if !os(tvOS)
            guard let url = choice.selected.url else { return }
            playback.stageSelection(url)
            isPreparingSelection = true
            preparation = Task { [weak self] in
                // A provider's coordinated enumeration may not cancel immediately.
                // Let its cleanup finish before reusing MediaLibrary's scan state.
                await previousPreparation?.value
                guard let self, !Task.isCancelled, self.preparationRevision == token else { return }
                defer { if self.preparationRevision == token { self.isPreparingSelection = false } }
                // Keep the selection grant until MediaLibrary has acquired its own.
                let grant = choice.access
                await self.library.open(root, loadPlaylist: false)
                withExtendedLifetime(grant) {}
                guard !Task.isCancelled, self.preparationRevision == token else { return }
                if let error = self.library.error {
                    self.playback.stageSelection(url)
                    self.playback.selectionFailed(error, accessFailure: self.library.needsFolderPermission)
                    return
                }
                await self.library.playFromSelection(url, autoplay: self.playback.interruptionRevision == interruption)
            }
            #endif
        case .dlna:
            #if !os(tvOS)
            library.releasePlaybackAccess()
            #endif
            var names: [URL: String] = [:]
            var sizes: [URL: Int64] = [:]
            var urls: [URL] = []
            for row in choice.rows where !row.isFolder {
                guard let url = row.url, names[url] == nil else { continue }
                urls.append(url); names[url] = row.name; sizes[url] = row.remote?.size
            }
            guard let url = choice.selected.url else { return }
            // Prefer the selected object name when multiple object IDs share a URL.
            names[url] = choice.selected.name
            playback.setPlaylist(urls, displayNames: names, sizes: sizes)
            playback.commitSelection(url)
        }
    }
    #if !os(tvOS)
    func startFixturesIfRequested() async {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-fixtures") || arguments.contains("--ui-real-samples") {
            let folder = arguments.contains("--ui-real-samples") ? "RealSamples"
                : arguments.contains("--ui-narrow-folder") ? "UIFixtures/SecondPlaylist" : "UIFixtures"
            let url = URL.documentsDirectory.appendingPathComponent(folder)
            await library.open(url, persist: false)
            _ = try? registrations.addLocal(url)
            showsFixturePlaylist = true
        }
        #endif
    }
    func chooseFixture(_ url: URL) {
        guard let root = library.folderURL else { return }
        let rows = library.files.map { SelectionRow(id: $0.standardizedFileURL.path, name: $0.lastPathComponent,
                                                    isFolder: false, url: $0, remote: nil) }
        guard let row = rows.first(where: { $0.url == url }) else { return }
        commit(MediaSelection(folder: .local(root: root, directory: url.deletingLastPathComponent()),
                              rows: rows, selected: row, access: BrowsingFolderAccess(root)))
    }
    #endif
}
