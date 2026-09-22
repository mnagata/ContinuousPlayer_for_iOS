import Foundation

@main struct EnumerationTests {
    static func main() async throws {
        func urls(_ names: [String]) -> [URL] { names.map { URL(fileURLWithPath: "/fixtures/\($0)") } }
        func sorted(_ names: [String]) -> [String] {
            PlaylistSorter.sort(urls(names), locale: Locale(identifier: "ja_JP")).map(\.lastPathComponent)
        }
        func expect(_ value: Bool, _ message: String) { precondition(value, message) }
        expect(sorted(["作品 ED2.mp4", "作品 OP10.mp4", "作品 ED.mp4", "作品 OP2.mp4", "作品 OP.mp4"]) ==
               ["作品 OP.mp4", "作品 ED.mp4", "作品 OP2.mp4", "作品 ED2.mp4", "作品 OP10.mp4"], "number/category ordering")
        expect(sorted(["A OP.mp4", "A Intro.mp4", "A ED.mp4"]) == ["A OP.mp4", "A Intro.mp4", "A ED.mp4"], "nonmatching slot")
        expect(PlaylistSorter.parse("Show.Name op02.MP4") == .init(base: "show.name", number: 2, category: 0), "case and final extension")
        expect(PlaylistSorter.parse(" Show ED .mp4")?.number == 1, "trim/default")
        expect(PlaylistSorter.parse("Show OP2147483648.mp4")?.number == 1, "Android Int overflow fallback")
        expect(PlaylistSorter.parse("Show OP0.mp4")?.number == 0, "zero")
        for name in ["ShowOP.mp4", "Show OP 2.mp4", "Show OP2 extra.mp4", "Show OP２.mp4"] {
            expect(PlaylistSorter.parse(name) == nil, "nonmatch: \(name)")
        }
        expect(sorted(["a op.mp4", "A OP.mp4"]) == ["a op.mp4", "A OP.mp4"], "stable equal rank")
        expect(sorted(["B ED.mp4", "A ED.mp4", "B OP.mp4", "A OP.mp4"]) ==
               ["A OP.mp4", "A ED.mp4", "B OP.mp4", "B ED.mp4"], "independent groups")
        expect(sorted([]).isEmpty, "empty")
        let seasonal = ["アニメOPED 2025秋", "アニメOPED 2025夏", "アニメOPED 2025冬", "アニメOPED 2025春", "アニメOPED 2024秋", "アニメOPED 2026年冬"]
        let expectedSeasons = ["アニメOPED 2024秋", "アニメOPED 2025冬", "アニメOPED 2025春", "アニメOPED 2025夏", "アニメOPED 2025秋", "アニメOPED 2026年冬"]
        expect(MediaScanner.sortFolders(urls(seasonal)).map(\.lastPathComponent) == expectedSeasons, "year then winter/spring/summer/autumn")
        let ordinary = urls(["資料10", "春の作品", "資料2", "冬の作品", "アニメOPED 2025"])
        let ordinarySorted = ordinary.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        expect(MediaScanner.sortFolders(ordinary) == ordinarySorted, "ordinary folder order unchanged")
        let mixed = urls(seasonal) + ordinary + urls(["別作品 2025秋", "別作品 2025冬"])
        let mixedSorted = MediaScanner.sortFolders(mixed)
        expect(mixedSorted.filter { seasonal.contains($0.lastPathComponent) }.map(\.lastPathComponent) == expectedSeasons, "mixed seasonal group")
        expect(mixedSorted.filter { ordinary.contains($0) } == ordinarySorted, "mixed ordinary order")
        expect(mixedSorted.filter { $0.lastPathComponent.hasPrefix("別作品") }.map(\.lastPathComponent) == ["別作品 2025冬", "別作品 2025秋"], "independent seasonal prefix")
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let supported = ["A ED.mp4", "A OP.MP4", ".hidden.wav", "audio.m4v", "audio.mp3", "audio.flac", "audio.m4a", "audio.aac", "audio.ogg", "audio.opus"]
        for name in supported + ["._A OP.mp4", "notes.txt", "noextension"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        let child = root.appendingPathComponent("folder.mp4")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data().write(to: child.appendingPathComponent("nested.mp4"))
        let scanned = try await MediaScanner.scan(root)
        expect(Set(scanned.map(\.lastPathComponent)) == Set(supported), "direct regular files/filter/hidden")
        expect(scanned.firstIndex(where: { $0.lastPathComponent == "A OP.MP4" })! < scanned.firstIndex(where: { $0.lastPathComponent == "A ED.mp4" })!, "scanner uses sorter")
        let selected = scanned.first(where: { $0.lastPathComponent == "A ED.mp4" })!
        expect(scanned.firstIndex(of: selected) != nil, "selection retains URL identity")
        do {
            _ = try await MediaScanner.scan(root.appendingPathComponent("missing"))
            preconditionFailure("missing folder must fail")
        } catch { }
        let outside = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("outside"), withDestinationURL: outside)
        let browsed = try await MediaScanner.browse(root, within: root)
        expect(browsed.folders.map { $0.standardizedFileURL.path } == [child.standardizedFileURL.path], "browser shows child folders and excludes external links")
        expect(browsed.files == scanned.filter { !$0.lastPathComponent.hasPrefix(".") }, "browser preserves playback order and hides hidden files")
        let nested = try await MediaScanner.browse(child, within: root)
        expect(nested.files.map(\.lastPathComponent) == ["nested.mp4"], "browse subfolder")
        do {
            _ = try await MediaScanner.browse(outside, within: root)
            preconditionFailure("browser must reject directories outside permission root")
        } catch { }
        for name in seasonal {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let seasonalBrowse = try await MediaScanner.browse(root, within: root)
        expect(seasonalBrowse.folders.filter { seasonal.contains($0.lastPathComponent) }.map(\.lastPathComponent) == expectedSeasons, "browser applies seasonal sort")
        print("PASS: seasonal folder ordering; browser navigation, scope boundary, filtering; OP/ED ordering, stable slots, parsing boundaries, scanner filtering, selection and access failure")
    }
}
