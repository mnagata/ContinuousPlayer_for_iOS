import Foundation

/// Name ordering followed by slot-preserving OP/ED ordering, matching Android.
nonisolated enum PlaylistSorter {
    struct OpEd: Equatable {
        let base: String
        let number: Int32
        let category: Int
    }

    static func parse(_ name: String) -> OpEd? {
        let stem = (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        // ASCII digits match Java's default regex semantics.
        let expression = try! NSRegularExpression(pattern: #"^(.+?)\s+(OP|ED)([0-9]*)$"#, options: .caseInsensitive)
        guard let match = expression.firstMatch(in: stem, range: NSRange(stem.startIndex..., in: stem)),
              match.range.length == stem.utf16.count else { return nil }
        func group(_ index: Int) -> String { String(stem[Range(match.range(at: index), in: stem)!]) }
        return OpEd(base: group(1).trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                    number: Int32(group(3)) ?? 1, category: group(2).uppercased() == "OP" ? 0 : 1)
    }

    static func sort(_ files: [URL], locale: Locale = .current) -> [URL] {
        // No numeric option: Android's Collator compares ordinary names lexically.
        var result = files.enumerated().sorted {
            let order = $0.element.lastPathComponent.compare($1.element.lastPathComponent,
                options: .caseInsensitive, locale: locale)
            return order == .orderedSame ? $0.offset < $1.offset : order == .orderedAscending
        }.map(\.element)
        var groups: [String: [(index: Int, info: OpEd)]] = [:]
        for (index, file) in result.enumerated() {
            if let info = parse(file.lastPathComponent) {
                groups[info.base, default: []].append((index, info))
            }
        }
        for positions in groups.values {
            let reordered = positions.sorted {
                if $0.info.number != $1.info.number { return $0.info.number < $1.info.number }
                if $0.info.category != $1.info.category { return $0.info.category < $1.info.category }
                return $0.index < $1.index
            }.map { result[$0.index] }
            for (position, file) in zip(positions, reordered) { result[position.index] = file }
        }
        return result
    }
}
