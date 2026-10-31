import Foundation
import Observation

/// Identity is the server/object pair, never the media URL (which may be shared).
struct SelectionRow: Identifiable, Hashable {
    let id: String
    let name: String
    let isFolder: Bool
    let url: URL?
    let remote: DLNAEntry?
}

enum SelectionFolder: Hashable {
    enum Identity: Hashable {
        case local(root: String, directory: String)
        case dlna(server: String, root: [String], path: [String], adding: Bool)
    }
    var identity: Identity {
        switch self {
        case .local(let root, let directory):
            .local(root: root.standardizedFileURL.path, directory: directory.standardizedFileURL.path)
        case .dlna(let server, let root, let path, let adding):
            .dlna(server: server.id, root: root.map(\.id), path: path.map(\.id), adding: adding)
        }
    }

    case local(root: URL, directory: URL)
    case dlna(server: DLNAServer, root: [RegisteredDLNAPath], path: [RegisteredDLNAPath], adding: Bool)

    var title: String {
        switch self {
        case .local(_, let directory): directory.lastPathComponent
        case .dlna(let server, _, let path, _): path.last?.title ?? server.name
        }
    }
    var isAdding: Bool {
        if case .dlna(_, _, _, let adding) = self { return adding }
        return false
    }
    var parent: SelectionFolder? {
        switch self {
        case .local(let root, let directory):
            guard directory.standardizedFileURL != root.standardizedFileURL else { return nil }
            return .local(root: root, directory: directory.deletingLastPathComponent())
        case .dlna(let server, let root, let path, let adding):
            guard path.count > root.count else { return nil }
            return .dlna(server: server, root: root, path: Array(path.dropLast()), adding: adding)
        }
    }
}

struct MediaSelection {
    let folder: SelectionFolder
    let rows: [SelectionRow]
    let selected: SelectionRow
    let access: BrowsingFolderAccess?
}

/// A browsing grant has its own lifetime. Removing a bookmark cannot release the
/// independent grant retained by the active MediaLibrary.
final class BrowsingFolderAccess {
    let url: URL
    private let acquired: Bool
    init(_ url: URL) { self.url = url; acquired = url.startAccessingSecurityScopedResource() }
    deinit { if acquired { url.stopAccessingSecurityScopedResource() } }
}

@MainActor @Observable
final class FileSelectionCoordinator {
    enum Origin { case home, playback }
    enum Page: Equatable { case saved, sources, servers, folder(SelectionFolder) }
    let origin: Origin
    let registrations: RegisteredFolders
    private(set) var page: Page = .saved
    private(set) var rows: [SelectionRow] = []
    private(set) var isLoading = false
    private(set) var showsLoading = false
    private(set) var isClosed = false
    var isConnecting = false
    var error: String?
    var selectedSavedID: String?
    var selectedRowID: String?
    private(set) var focusRevision = 0
    private(set) var requestRevision = 0
    private var lastSelections: [SelectionFolder.Identity: String] = [:]
    private var cache: [SelectionFolder: [SelectionRow]] = [:]
    private var access: [URL: BrowsingFolderAccess] = [:]
    @ObservationIgnored private var request: Task<Void, Never>?
    @ObservationIgnored private var indicator: Task<Void, Never>?
    @ObservationIgnored private let browse: (SelectionFolder) async throws -> [SelectionRow]
    @ObservationIgnored private let reconnect: (RegisteredDLNAFolder) async throws -> DLNAServer
    @ObservationIgnored private let choose: (MediaSelection) -> Void
    @ObservationIgnored private let cancelled: () -> Void
    var busy: Bool { isLoading || isConnecting }
    func revealSelection() { focusRevision += 1 }

    init(origin: Origin, registrations: RegisteredFolders,
         browse: @escaping (SelectionFolder) async throws -> [SelectionRow] = FileSelectionCoordinator.readFolder,
         reconnect: @escaping (RegisteredDLNAFolder) async throws -> DLNAServer = FileSelectionCoordinator.reconnectFolder,
         choose: @escaping (MediaSelection) -> Void, cancelled: @escaping () -> Void) {
        self.origin = origin; self.registrations = registrations
        self.browse = browse; self.reconnect = reconnect
        self.choose = choose; self.cancelled = cancelled
    }

    var savedIDs: [String] {
        registrations.local.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map { "saved.local.\($0.id)" } +
        registrations.dlna.sorted { $0.detail.localizedStandardCompare($1.detail) == .orderedAscending }.map { "saved.dlna.\($0.id)" }
    }
    var title: String {
        switch page {
        case .saved: "保存済みフォルダー"
        case .sources: "フォルダーを追加"
        case .servers: "DLNAサーバー"
        case .folder(let folder): folder.title
        }
    }
    var parentTitle: String {
        switch page {
        case .saved: ""
        case .sources: "保存済みフォルダー"
        case .servers: "フォルダーを追加"
        case .folder(let folder): folder.parent?.title ?? (folder.isAdding ? "DLNAサーバー" : "保存済みフォルダー")
        }
    }

    func showSources() { guard !busy, !isClosed else { return }; page = .sources; error = nil }
    func showServers() { guard !busy, !isClosed else { return }; page = .servers; error = nil }
    func showSaved(select id: String? = nil) {
        invalidateRequest()
        guard !isClosed else { return }
        page = .saved; rows = []; error = nil
        let preferred = id ?? selectedSavedID
        selectedSavedID = preferred.flatMap { savedIDs.contains($0) || $0 == "saved.addFolder" ? $0 : nil }
            ?? savedIDs.first ?? "saved.addFolder"
        focusRevision += 1
    }

    func open(_ folder: RegisteredLocalFolder) {
        guard !busy, !isClosed else { return }
        selectedSavedID = "saved.local.\(folder.id)"
        do {
            let url = try registrations.resolve(folder)
            retainAccess(url)
            load(.local(root: url, directory: url))
        } catch { self.error = "登録したフォルダーを開けません。再登録してください。\(error.localizedDescription)" }
    }
    func open(_ folder: RegisteredDLNAFolder) {
        guard !busy, !isClosed else { return }
        selectedSavedID = "saved.dlna.\(folder.id)"
        let token = beginRequest()
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let server = try await self.reconnect(folder)
                guard self.accepts(token) else { return }
                guard !folder.path.isEmpty else { throw DLNAError.message("保存した階層がありません。再登録してください。") }
                let location = SelectionFolder.dlna(server: server, root: folder.path, path: folder.path, adding: false)
                let result = try await self.browse(location)
                guard self.accepts(token) else { return }
                self.apply(result, folder: location)
            } catch { self.fail(error, token: token) }
        }
    }
    func openServer(_ server: DLNAServer) {
        guard !busy, !isClosed else { return }
        let root = [RegisteredDLNAPath(id: "0", title: server.name)]
        load(.dlna(server: server, root: root, path: root, adding: true))
    }
    func openCurrent(_ folder: SelectionFolder, rowID: String?) {
        guard !isClosed else { return }
        switch folder {
        case .local(let root, _):
            retainAccess(root)
            if let registered = registrations.local.first(where: {
                (try? registrations.resolve($0).standardizedFileURL) == root.standardizedFileURL
            }) { selectedSavedID = "saved.local.\(registered.id)" }
        case .dlna(let server, let root, _, _):
            if let registered = registrations.dlna.first(where: { $0.serverID == server.id && $0.path.last?.id == root.last?.id }) {
                selectedSavedID = "saved.dlna.\(registered.id)"
            }
        }
        // The caller passes the original registration root, even if it was removed.
        page = .folder(folder); selectedRowID = rowID
        if let rowID { lastSelections[folder.identity] = rowID }
        load(folder)
    }
    func activate(_ row: SelectionRow) {
        guard !busy, !isClosed, rows.contains(row), case .folder(let folder) = page else { return }
        selectedRowID = row.id; lastSelections[folder.identity] = row.id
        if row.isFolder {
            switch folder {
            case .local(let root, _):
                guard let url = row.url else { return }
                load(.local(root: root, directory: url))
            case .dlna(let server, let root, let path, let adding):
                guard let entry = row.remote else { return }
                load(.dlna(server: server, root: root, path: path + [RegisteredDLNAPath(id: entry.id, title: entry.title)], adding: adding))
            }
        } else if !folder.isAdding {
            // End the entire selection flow, invalidating all asynchronous work.
            let grant: BrowsingFolderAccess?
            if case .local(let root, _) = folder { grant = access[root] } else { grant = nil }
            finish()
            choose(MediaSelection(folder: folder, rows: rows, selected: row, access: grant))
        }
    }
    func reload() { guard !busy, case .folder(let folder) = page else { return }; load(folder, refresh: true) }
    func back() {
        guard !isClosed else { return }
        if busy { cancel(); return }
        error = nil
        switch page {
        case .saved: cancel()
        case .sources: showSaved()
        case .servers: page = .sources
        case .folder(let folder):
            if let parent = folder.parent { load(parent) }
            else if folder.isAdding { page = .servers; rows = [] }
            else { showSaved() }
        }
    }
    func cancelPage() {
        guard !isClosed else { return }
        if busy { cancel(); return }
        switch page {
        case .sources, .servers: showSaved()
        case .folder(let folder) where folder.isAdding: showSaved()
        default: cancel()
        }
    }
    func cancel() { guard !isClosed else { return }; finish(); cancelled() }
    func finish() { invalidateRequest(); isClosed = true; access.removeAll() }

    func registerCurrent() {
        guard !busy, !isClosed, case .folder(.dlna(let server, _, let path, true)) = page else { return }
        let folder = registrations.addDLNA(server: server, path: path)
        showSaved(select: "saved.dlna.\(folder.id)")
    }
    func registerLocal(_ url: URL) {
        guard !busy, !isClosed else { return }
        do {
            let folder = try registrations.addLocal(url)
            showSaved(select: "saved.local.\(folder.id)")
        } catch { self.error = "フォルダーの登録に失敗しました。\(error.localizedDescription)" }
    }
    func removeLocal(_ folder: RegisteredLocalFolder) {
        guard !busy, !isClosed else { return }
        let id = "saved.local.\(folder.id)"; let next = focusAfterRemoving(id)
        registrations.removeLocal(folder)
        selectedSavedID = next; focusRevision += 1
    }
    func removeDLNA(_ folder: RegisteredDLNAFolder) {
        guard !busy, !isClosed else { return }
        let id = "saved.dlna.\(folder.id)"; let next = focusAfterRemoving(id)
        registrations.removeDLNA(folder)
        selectedSavedID = next; focusRevision += 1
    }
    private func focusAfterRemoving(_ id: String) -> String {
        let ids = savedIDs
        guard let index = ids.firstIndex(of: id) else { return ids.first ?? "saved.addFolder" }
        if index + 1 < ids.count { return ids[index + 1] }
        if index > 0 { return ids[index - 1] }
        return "saved.addFolder"
    }
    private func retainAccess(_ url: URL) { if access[url] == nil { access[url] = BrowsingFolderAccess(url) } }

    private func load(_ folder: SelectionFolder, refresh: Bool = false) {
        let token = beginRequest()
        if !refresh, let cached = cache[folder] { apply(cached, folder: folder); return }
        request = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await self.browse(folder)
                guard self.accepts(token) else { return }
                self.apply(result, folder: folder)
            } catch { self.fail(error, token: token) }
        }
    }
    private func beginRequest() -> Int {
        invalidateRequest()
        isLoading = true; error = nil
        let token = requestRevision
        indicator = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self, self.isLoading, self.requestRevision == token else { return }
            self.showsLoading = true
        }
        return token
    }
    private func accepts(_ token: Int) -> Bool { !isClosed && !Task.isCancelled && requestRevision == token }
    private func apply(_ result: [SelectionRow], folder: SelectionFolder) {
        cache[folder] = result; rows = result; page = .folder(folder)
        selectedRowID = lastSelections[folder.identity] ?? result.first?.id
        isLoading = false; showsLoading = false; indicator?.cancel(); focusRevision += 1
    }
    private func fail(_ error: Error, token: Int) {
        guard accepts(token) else { return }
        self.error = error.localizedDescription
        isLoading = false; showsLoading = false; indicator?.cancel()
    }
    private func invalidateRequest() {
        requestRevision += 1; request?.cancel(); indicator?.cancel()
        request = nil; indicator = nil; isLoading = false; showsLoading = false
    }

    static func readFolder(_ folder: SelectionFolder) async throws -> [SelectionRow] {
        switch folder {
        case .local(let root, let directory):
            let result = try await MediaScanner.browse(directory, within: root)
            return (result.folders + result.files).map {
                SelectionRow(id: $0.standardizedFileURL.path, name: $0.lastPathComponent,
                             isFolder: result.folders.contains($0), url: $0, remote: nil)
            }
        case .dlna(let server, _, let path, _):
            let result = try await DLNAClient().browse(server, objectID: path.last?.id ?? "0")
            let folders = MediaScanner.sortFolders(result.filter(\.isContainer), name: { $0.title })
            let files = PlaylistSorter.sort(result.filter { !$0.isContainer && $0.resourceURL != nil }, name: { $0.title }, namesAreTitles: true)
            return (folders + files).map { SelectionRow(id: server.id + "|" + $0.id, name: $0.title,
                isFolder: $0.isContainer, url: $0.resourceURL, remote: $0) }
        }
    }
    static func reconnectFolder(_ folder: RegisteredDLNAFolder) async throws -> DLNAServer {
        let client = DLNAClient()
        if let server = try? await client.server(at: folder.descriptionURL), server.id == folder.serverID { return server }
        try Task.checkCancellation()
        if DLNADiscovery.isAvailable {
            for url in try await DLNADiscovery.locations() {
                try Task.checkCancellation()
                if let server = try? await client.server(at: url), server.id == folder.serverID { return server }
            }
        }
        throw DLNAError.message("登録したNASへの接続とアクセス許可を確認してください。")
    }
}
