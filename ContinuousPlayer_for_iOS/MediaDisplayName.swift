import Foundation

/// Server titles and local filenames follow the same suffix rule. Folder names
/// and unknown suffixes are preserved, including periods inside a title.
nonisolated enum MediaDisplayName {
    static func title(_ name: String) -> String {
        let value = name as NSString
        guard MediaScanner.extensions.contains(value.pathExtension.lowercased()) else { return name }
        let title = value.deletingPathExtension
        return title.isEmpty ? name : title
    }
    static func format(_ name: String) -> String? {
        let suffix = (name as NSString).pathExtension.lowercased()
        return MediaScanner.extensions.contains(suffix) ? suffix.uppercased() : nil
    }
    static func collisions(in names: [String]) -> Set<String> {
        let groups = Dictionary(grouping: names, by: title)
        return Set(groups.filter { $0.value.count > 1 }.keys)
    }
}
