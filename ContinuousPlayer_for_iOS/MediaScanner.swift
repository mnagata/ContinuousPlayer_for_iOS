import Foundation

nonisolated enum MediaScanner {
    static let extensions: Set<String> = ["mp4", "m4v", "mp3", "flac", "m4a", "aac", "wav", "ogg", "opus"]

    static func isSupported(_ url: URL) -> Bool {
        !url.lastPathComponent.hasPrefix("._") && extensions.contains(url.pathExtension.lowercased())
    }

    /// Keep ordinary name ordering, then order seasonal folders within each name prefix.
    static func sortFolders(_ folders: [URL]) -> [URL] {
        var sorted = folders.sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        let pattern = try! NSRegularExpression(pattern: #"^(.*?)([0-9]{4})\s*年?\s*([冬春夏秋])$"#)
        let seasons = ["冬": 0, "春": 1, "夏": 2, "秋": 3]
        var groups: [String: [(index: Int, year: Int, season: Int)]] = [:]
        for (index, url) in sorted.enumerated() {
            let name = url.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let match = pattern.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) else { continue }
            func group(_ number: Int) -> String { String(name[Range(match.range(at: number), in: name)!]) }
            let prefix = group(1).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            groups[prefix, default: []].append((index, Int(group(2))!, seasons[group(3)]!))
        }
        // Reorder matching slots only; a mixed comparator could violate transitivity.
        for positions in groups.values {
            let ordered = positions.sorted {
                if $0.year != $1.year { return $0.year < $1.year }
                if $0.season != $1.season { return $0.season < $1.season }
                return $0.index < $1.index
            }.map { sorted[$0.index] }
            for (position, url) in zip(positions, ordered) { sorted[position.index] = url }
        }
        return sorted
    }

    /// Resolve links before exposing entries so browsing cannot escape the granted root.
    static func browse(_ folder: URL, within root: URL) async throws -> (folders: [URL], files: [URL]) {
        try await Task.detached {
            let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
            func isAllowed(_ url: URL) -> Bool {
                let path = url.standardizedFileURL.resolvingSymlinksInPath().path
                return path == rootPath || path.hasPrefix(rootPath + "/")
            }
            guard isAllowed(folder) else { throw CocoaError(.fileReadNoPermission) }
            var result: Result<(folders: [URL], files: [URL]), Error>?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &coordinationError) { url in
                result = Result {
                    let entries = try FileManager.default.contentsOfDirectory(at: url,
                        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey], options: [.skipsHiddenFiles])
                    var folders: [URL] = []
                    var files: [URL] = []
                    for entry in entries where isAllowed(entry) {
                        let values = try entry.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
                        if values.isDirectory == true { folders.append(entry) }
                        else if values.isRegularFile == true && isSupported(entry) { files.append(entry) }
                    }
                    return (sortFolders(folders),
                            PlaylistSorter.sort(files))
                }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw CocoaError(.fileReadUnknown) }
            return try result.get()
        }.value
    }

    /// The caller retains security-scoped access until scanning and playback finish.
    static func scan(_ folder: URL) async throws -> [URL] {
        try await Task.detached {
            var result: Result<[URL], Error>?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: folder, options: [], error: &coordinationError) { url in
                result = Result {
                    let entries = try FileManager.default.contentsOfDirectory(at: url,
                        includingPropertiesForKeys: [.isRegularFileKey], options: [])
                    let files = try entries.filter {
                        guard isSupported($0) else { return false }
                        return try $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true
                    }
                    return PlaylistSorter.sort(files)
                }
            }
            if let coordinationError { throw coordinationError }
            guard let result else { throw CocoaError(.fileReadUnknown) }
            return try result.get()
        }.value
    }
}
