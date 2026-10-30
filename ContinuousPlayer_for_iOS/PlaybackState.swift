import Foundation

/// AVPlayerの待機状態と、ユーザーの再生意図を分けて保持する。
struct PlaybackState {
    private(set) var files: [URL] = []
    private(set) var index: Int?
    var wantsToPlay = false
    private(set) var ended = false

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

    /// Failure never changes the selected item. Only natural end advances it.
    mutating func failed() {
        wantsToPlay = false
        ended = false
    }
}

struct PlaybackFailure: Identifiable {
    enum Recovery { case media, localAccess, network, audioOutput }
    let id = UUID()
    let url: URL
    let name: String
    let reason: String
    let seconds: Double
    let recovery: Recovery
    var message: String { "\(name): \(reason)" }
    var guidance: String {
        switch recovery {
        case .localAccess:
            "外部ストレージの接続を確認してください。アクセス許可が必要な場合は、ファイル一覧の保存済みフォルダーから登録し直し、「再試行」を選んでください。"
        case .network:
            "NASとネットワークの接続・アクセス許可を確認してください。再接続後は「再試行」で再開できます。"
        case .audioOutput:
            "音声出力機器の接続を確認し、「再試行」を選んでください。"
        case .media:
            "ファイルと保存先を確認してください。「再試行」で同じファイルを開き直せます。"
        }
    }
}

/// Pure boundary policy shared by transport, touch and keyboard commands.
enum PlaybackSeekPolicy {
    enum Action: Equatable { case none, position(Double), next }
    static func validRanges(_ ranges: [ClosedRange<Double>]) -> [ClosedRange<Double>] {
        ranges.filter { $0.lowerBound.isFinite && $0.upperBound.isFinite && $0.upperBound > max(0, $0.lowerBound) }
    }
    static func action(current: Double, by delta: Double, duration: Double?,
                       ranges: [ClosedRange<Double>], hasNext: Bool) -> Action {
        let ranges = validRanges(ranges)
        guard current.isFinite, delta.isFinite, !ranges.isEmpty else { return .none }
        let target = current + delta
        guard target.isFinite else { return .none }
        if let duration, duration.isFinite, duration > 0, delta > 0, target >= duration {
            return hasNext ? .next : .none
        }
        // Stay inside the current seekable segment; never infer a next file from
        // the edge of a live/unknown-length stream or jump across an unavailable gap.
        let range = ranges.first { $0.contains(current) } ?? ranges.min {
            abs(current - min(max(current, $0.lowerBound), $0.upperBound)) <
            abs(current - min(max(current, $1.lowerBound), $1.upperBound))
        }!
        return .position(min(max(target, max(0, range.lowerBound)), range.upperBound))
    }
}
