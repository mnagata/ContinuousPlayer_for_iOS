import Foundation
import CoreGraphics

enum PlaybackInputCommand: String {
    case previous, next, backward, forward, toggle, play, pause, browse, info, home
}

enum PlaybackKeyboardInput {
    enum Target { case video, controls, text, modal, list }
    static func command(_ key: String, shift: Bool = false, modified: Bool = false,
                        repeating: Bool = false, target: Target = .video) -> PlaybackInputCommand? {
        guard !modified, !repeating, target == .video else { return nil }
        switch key.lowercased() {
        case "left": return shift ? .backward : .previous
        case "right": return shift ? .forward : .next
        case "up": return .backward
        case "down": return .forward
        case " ", "return": return .toggle
        case "escape", "o": return .browse
        case "i": return .info
        case "h": return .home
        default: return nil
        }
    }
}

/// One physical contact owns its complete gesture. A drag or second finger can
/// never become a tap on release; pointer contacts never become media swipes.
struct PlaybackTouchInput {
    enum Source { case direct, pointer }
    private struct Contact {
        var start: CGPoint
        var time: Double
        var source: Source
        var active: Bool
        var distance = 0.0
        var cancelled = false
    }
    private struct Tap {
        let point: CGPoint
        let time: Double
        let region: Int
    }
    private var contact: Contact?
    private var lastTap: Tap?

    mutating func begin(at point: CGPoint, time: Double, source: Source, activeWindow: Bool = true) {
        guard contact == nil else { contact?.cancelled = true; return }
        contact = Contact(start: point, time: time, source: source, active: activeWindow)
    }
    mutating func move(to point: CGPoint) {
        guard let current = contact else { return }
        contact?.distance = max(current.distance, hypot(point.x - current.start.x, point.y - current.start.y))
    }
    mutating func cancel() { contact = nil; lastTap = nil }
    mutating func end(at point: CGPoint, time: Double, width: Double, clickCount: Int = 1) -> PlaybackInputCommand? {
        move(to: point)
        guard let current = contact else { return nil }
        contact = nil
        guard !current.cancelled, width > 0 else { lastTap = nil; return nil }
        if current.source == .pointer {
            lastTap = nil
            return current.active && current.distance < 6 && clickCount <= 1 ? .toggle : nil
        }
        let dx = point.x - current.start.x, dy = point.y - current.start.y
        if current.distance >= 10 {
            lastTap = nil
            guard abs(dx) >= 70, abs(dx) >= abs(dy) * 1.5 else { return nil }
            return dx < 0 ? .next : .previous
        }
        guard time - current.time < 0.6 else { lastTap = nil; return nil }
        let region = min(2, max(0, Int(current.start.x / width * 3)))
        if let tap = lastTap, tap.region == region, time - tap.time >= 0, time - tap.time <= 0.3,
           hypot(point.x - tap.point.x, point.y - tap.point.y) <= 32 {
            lastTap = nil
            return nil
        }
        lastTap = Tap(point: point, time: time, region: region)
        return [.backward, .toggle, .forward][region]
    }
}

/// Correlate a directional press with its active indirect-touch sequence,
/// rather than discarding unrelated fast inputs using a time window.
struct TVDirectionalInput {
    private var held: Set<Int> = []
    private var touching = false
    private var touchHadPress = false
    mutating func touchBegan() { touching = true; touchHadPress = false }
    mutating func press(_ id: Int, command: PlaybackInputCommand) -> PlaybackInputCommand? {
        guard held.insert(id).inserted else { return nil }
        if touching { touchHadPress = true }
        return command
    }
    mutating func release(_ id: Int) { held.remove(id) }
    mutating func touchEnded(command: PlaybackInputCommand?) -> PlaybackInputCommand? {
        defer { touching = false; touchHadPress = false }
        return touchHadPress ? nil : command
    }
    mutating func reset() { self = TVDirectionalInput() }
}

enum FileListInput {
    static func pageSize(frames: [CGRect], viewport: CGRect) -> Int {
        max(1, frames.filter { frame in
            let visible = frame.intersection(viewport)
            return !visible.isNull && visible.height >= frame.height * 0.6
        }.count)
    }
    static func destination(ids: [String], selected: String?, offset: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        let current = selected.flatMap { ids.firstIndex(of: $0) } ?? 0
        return ids[min(ids.count - 1, max(0, current + offset))]
    }
}
