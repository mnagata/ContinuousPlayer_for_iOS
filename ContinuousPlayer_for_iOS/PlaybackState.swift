import Foundation

/// AVPlayerの待機状態と、ユーザーの再生意図を分けて保持する。
struct PlaybackState {
    private(set) var files: [URL] = []
    private(set) var index: Int?
    var wantsToPlay = false
    private(set) var ended = false
    private(set) var consecutiveFailures = 0

    var currentURL: URL? { index.map { files[$0] } }
    var canGoBack: Bool { (index ?? 0) > 0 }
    var canGoForward: Bool { index.map { $0 + 1 < files.count } ?? false }

    mutating func replace(_ files: [URL]) {
        self = PlaybackState()
        self.files = files
    }

    @discardableResult mutating func select(_ url: URL) -> Bool {
        guard let index = files.firstIndex(of: url) else { return false }
        self.index = index
        wantsToPlay = true
        ended = false
        consecutiveFailures = 0
        return true
    }

    @discardableResult mutating func move(_ offset: Int) -> Bool {
        guard let index, files.indices.contains(index + offset) else { return false }
        self.index = index + offset
        ended = false
        return true
    }

    mutating func finish() {
        ended = true
        wantsToPlay = false
    }

    mutating func didProgress() { consecutiveFailures = 0 }

    /// 3件連続失敗、または末尾の失敗で停止。
    mutating func failed() -> Bool {
        consecutiveFailures += 1
        if consecutiveFailures < 3, move(1) { return true }
        wantsToPlay = false
        return false
    }
}
