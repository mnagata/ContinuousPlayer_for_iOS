import Foundation
import Observation

struct RegisteredLocalFolder: Codable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let bookmark: Data
}

struct RegisteredDLNAPath: Codable, Hashable {
    let id: String
    let title: String
}

struct RegisteredDLNAFolder: Codable, Identifiable, Hashable {
    let serverID: String
    let serverName: String
    let descriptionURL: URL
    let path: [RegisteredDLNAPath]

    var id: String { serverID + "\u{0}" + (path.last?.id ?? "") }
    var name: String { path.last?.title ?? serverName }
    var detail: String { serverName + " · " + path.map(\.title).joined(separator: " / ") }
}

/// Stores folder identities and access grants; the selected playback folder stays in MediaLibrary.
@MainActor @Observable
final class RegisteredFolders {
    private(set) var local: [RegisteredLocalFolder] = []
    private(set) var dlna: [RegisteredDLNAFolder] = []
    private let defaults: UserDefaults
    private let localKey: String
    private let dlnaKey: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        #if DEBUG
        let prefix = ProcessInfo.processInfo.arguments.contains("--ui-bookmark-tests") ? "uitests." : ""
        #else
        let prefix = ""
        #endif
        localKey = prefix + "registered.localFolders.v1"
        dlnaKey = prefix + "registered.dlnaFolders.v1"
        if let data = defaults.data(forKey: localKey) {
            local = (try? JSONDecoder().decode([RegisteredLocalFolder].self, from: data)) ?? []
        } else {
            let legacyKey = prefix.isEmpty ? "validation.folder.bookmark" : "uitests.folder.bookmark"
            if let bookmark = defaults.data(forKey: legacyKey) {
                let name = (try? Self.resolve(bookmark).lastPathComponent) ?? "以前のフォルダー"
                local = [RegisteredLocalFolder(id: UUID(), name: name, bookmark: bookmark)]
                persistLocal()
            }
        }
        if let data = defaults.data(forKey: dlnaKey) {
            dlna = (try? JSONDecoder().decode([RegisteredDLNAFolder].self, from: data)) ?? []
        }
    }

    func addLocal(_ url: URL) throws {
        #if targetEnvironment(macCatalyst)
        let options: URL.BookmarkCreationOptions = [.withSecurityScope, .securityScopeAllowOnlyReadAccess]
        #else
        let options: URL.BookmarkCreationOptions = .minimalBookmark
        #endif
        let bookmark = try url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil)
        if let index = local.firstIndex(where: { (try? Self.resolve($0.bookmark).standardizedFileURL) == url.standardizedFileURL }) {
            local[index] = RegisteredLocalFolder(id: local[index].id, name: url.lastPathComponent, bookmark: bookmark)
        } else {
            local.append(RegisteredLocalFolder(id: UUID(), name: url.lastPathComponent, bookmark: bookmark))
        }
        persistLocal()
    }

    func resolve(_ folder: RegisteredLocalFolder) throws -> URL { try Self.resolve(folder.bookmark) }

    func removeLocal(_ folder: RegisteredLocalFolder) {
        local.removeAll { $0.id == folder.id }
        persistLocal()
    }

    func contains(_ server: DLNAServer, objectID: String) -> Bool {
        dlna.contains { $0.serverID == server.id && $0.path.last?.id == objectID }
    }

    func toggleDLNA(server: DLNAServer, path: [RegisteredDLNAPath]) {
        guard let last = path.last else { return }
        let id = server.id + "\u{0}" + last.id
        if dlna.contains(where: { $0.id == id }) {
            dlna.removeAll { $0.id == id }
        } else {
            dlna.append(RegisteredDLNAFolder(serverID: server.id, serverName: server.name,
                                             descriptionURL: server.descriptionURL, path: path))
        }
        persistDLNA()
    }

    func removeDLNA(_ folder: RegisteredDLNAFolder) {
        dlna.removeAll { $0.id == folder.id }
        persistDLNA()
    }

    private func persistLocal() { defaults.set(try? JSONEncoder().encode(local), forKey: localKey) }
    private func persistDLNA() { defaults.set(try? JSONEncoder().encode(dlna), forKey: dlnaKey) }

    private static func resolve(_ data: Data) throws -> URL {
        var stale = false
        #if targetEnvironment(macCatalyst)
        let options: URL.BookmarkResolutionOptions = [.withoutUI, .withSecurityScope]
        #else
        let options: URL.BookmarkResolutionOptions = .withoutUI
        #endif
        return try URL(resolvingBookmarkData: data, options: options, relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}
