import AVFoundation
import Observation
import OSLog

@MainActor @Observable
final class PlaybackController {
    private(set) var player = AVPlayer()
    private(set) var state = PlaybackState()
    private(set) var volumePercent = 100
    private(set) var failure: PlaybackFailure?
    private(set) var showsFailure = false
    var error: String? { failure?.message }
    private(set) var isLoading = false
    private(set) var mediaInfo = MediaInfo()
    private var displayNames: [URL: String] = [:]
    private var resourceSizes: [URL: Int64] = [:]
    private var preparation: Task<Void, Never>?
    private let logger = Logger(subsystem: "jp.nagu.ContinuousPlayer-for-iOS", category: "PlaybackStartup")
    private var statusObservation: NSKeyValueObservation?
    private var rangeObservation: NSKeyValueObservation?
    private var durationObservation: NSKeyValueObservation?
    private var notifications: [NSObjectProtocol] = []
    private var progressObserver: Any?
    private var timeout: Task<Void, Never>?
    private var generation = 0
    private var lastProgress = 0.0
    private var systemNotifications: [NSObjectProtocol] = []
    private var watchdog: Task<Void, Never>?
    private var lastAdvance = ContinuousClock.now
    private var isActive = true
    private var interrupted = false
    private(set) var interruptionRevision = 0
    private(set) var sessionRevision = 0
    private var presentationRevision = 0
    private var presentations: [UUID: PresentationSnapshot] = [:]
    private(set) var confirmedSeconds = 0.0
    private(set) var seekableRanges: [ClosedRange<Double>] = []
    private(set) var duration: Double?
    private(set) var isSeeking = false
    private var seekRevision = 0
    private var seekTask: Task<Void, Never>?
    private let preparationLimit: Duration
    private let performSeek: (AVPlayer, CMTime) async -> Bool
    var canSeek: Bool { !isPresenting && !isLoading && failure == nil && !seekableRanges.isEmpty }
    var canRetry: Bool { state.currentURL != nil && !isLoading && !isPresenting && isActive && !interrupted }
    var canResume: Bool { state.currentURL != nil && !isPresenting && isActive && !interrupted && (!needsFolderSelection || failure != nil) }

    struct PresentationSnapshot {
        let id: UUID
        let sessionRevision: Int
        let interruptionRevision: Int
        let generation: Int
        let url: URL?
        let seconds: Double
        let shouldResume: Bool
    }

    var isPresenting: Bool { !presentations.isEmpty }
    var allowsPlayback: Bool { isActive && !interrupted && !needsFolderSelection }

    /// The engine and source grants remain owned by the scene while UI is on top.
    func beginPresentation() -> PresentationSnapshot {
        let snapshot = PresentationSnapshot(id: UUID(), sessionRevision: sessionRevision,
            interruptionRevision: interruptionRevision, generation: generation,
            url: state.currentURL, seconds: player.currentTime().seconds,
            shouldResume: state.wantsToPlay && !state.ended && error == nil)
        presentations[snapshot.id] = snapshot
        presentationRevision += 1
        pause()
        return snapshot
    }

    func endPresentation(_ snapshot: PresentationSnapshot) {
        guard presentations.removeValue(forKey: snapshot.id) != nil else { return }
        presentationRevision += 1
        guard presentations.isEmpty, snapshot.sessionRevision == sessionRevision,
              snapshot.interruptionRevision == interruptionRevision,
              snapshot.generation == generation, snapshot.url == state.currentURL,
              snapshot.shouldResume, error == nil else { return }
        resume()
    }

    func discardPresentations() {
        presentations.removeAll()
        presentationRevision += 1
    }

    func stopSession() { setPlaylist([]) }

    /// Commit a user selection. Failure must remain attached to this selection.
    func commitSelection(_ url: URL, autoplay: Bool = true) {
        discardPresentations()
        select(url, autoplay: autoplay && isActive && !interrupted)
    }

    func stageSelection(_ url: URL) {
        setPlaylist([url])
        _ = state.select(url)
        state.wantsToPlay = false
    }

    func selectionFailed(_ message: String, accessFailure: Bool = false) {
        recordFailure(message, recovery: accessFailure ? .localAccess : nil)
    }
    #if os(iOS) || os(tvOS)
    private var audioSessionReady = false
    private var audioSessionGeneration = 0
    private var audioSessionActivation: Task<Void, Never>?
    #endif
    private(set) var pauseReason: String?
    private(set) var needsFolderSelection = false
    private(set) var isBuffering = false
    var showsPauseControls: Bool {
        state.currentURL != nil && !state.wantsToPlay && !state.ended && !needsFolderSelection
    }

    init(preparationLimit: Duration = .seconds(30),
         seek: @escaping (AVPlayer, CMTime) async -> Bool = {
             await $0.seek(to: $1, toleranceBefore: .zero, toleranceAfter: .zero)
         }) {
        self.preparationLimit = preparationLimit
        self.performSeek = seek
        #if os(iOS) || os(tvOS)
        let center = NotificationCenter.default
        systemNotifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            MainActor.assumeIsolated { self?.setInterrupted(began) }
        })
        systemNotifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            MainActor.assumeIsolated { self?.outputDisconnected() }
        })
        systemNotifications.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.interruptionRevision += 1
                self?.invalidateAudioSession()
                self?.pause()
                self?.clearItem()
                self?.player = AVPlayer()
                if let self { self.player.volume = Float(self.volumePercent) / 100 }
                self?.interrupted = false
                self?.pauseReason = "音声サービスが再起動しました。再生ボタンで再開できます。"
            }
        })
        #endif
    }

    func setActive(_ active: Bool) {
        guard active != isActive else { return }
        isActive = active
        if !active {
            interruptionRevision += 1
            #if os(iOS) || os(tvOS)
            invalidateAudioSession()
            #endif
            pause()
            pauseReason = "アプリが非アクティブになったため停止しました。"
        }
    }

    func setInterrupted(_ value: Bool) {
        interrupted = value
        if value {
            interruptionRevision += 1
            #if os(iOS) || os(tvOS)
            invalidateAudioSession()
            #endif
            pause()
            pauseReason = "音声の割り込みで停止しました。割り込み終了後、手動で再開してください。"
        }
    }

    func outputDisconnected() {
        interruptionRevision += 1
        #if os(iOS) || os(tvOS)
        invalidateAudioSession()
        #endif
        pause()
        pauseReason = "音声出力機器が切断されました。再生ボタンで再開できます。"
    }

    private func startPlayback() {
        guard isActive, !interrupted, !needsFolderSelection else {
            state.wantsToPlay = false
            return
        }
        guard !isLoading, state.wantsToPlay, !isPresenting, failure == nil else { return }
        #if os(iOS) || os(tvOS)
        guard audioSessionReady else {
            activateAudioSession()
            return
        }
        #endif
        pauseReason = nil
        lastAdvance = .now
        player.play()
    }

    #if os(iOS) || os(tvOS)
    private func invalidateAudioSession() {
        audioSessionGeneration += 1
        audioSessionReady = false
    }

    private func activateAudioSession() {
        guard audioSessionActivation == nil else { return }
        let sessionGeneration = audioSessionGeneration
        audioSessionActivation = Task { [weak self] in
            // These synchronous AVAudioSession calls can block, especially on Catalyst.
            let result = await Task.detached(priority: .userInitiated) { () -> Result<Void, Error> in
                Result {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .moviePlayback)
                    try session.setActive(true)
                }
            }.value
            guard let self else { return }
            self.audioSessionActivation = nil
            guard self.audioSessionGeneration == sessionGeneration else {
                if self.state.wantsToPlay { self.startPlayback() }
                return
            }
            switch result {
            case .success:
                self.audioSessionReady = true
                self.startPlayback()
            case .failure(let error):
                guard self.state.wantsToPlay else { return }
                self.recordFailure("音声出力を開始できません: \(error.localizedDescription)", recovery: .audioOutput)
            }
        }
    }
    #endif

    /// File-provider errors may wrap a Cocoa/POSIX access failure.
    nonisolated static func isAccessFailure(_ error: Error?) -> Bool {
        var current = error as NSError?
        for _ in 0..<8 {
            guard let value = current else { return false }
            if value.domain == NSCocoaErrorDomain && value.code == NSFileReadNoPermissionError { return true }
            if value.domain == NSPOSIXErrorDomain && [1, 6, 13, 19].contains(value.code) { return true }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    func accessFailed() {
        interruptionRevision += 1
        recordFailure("フォルダーへのアクセスが失われました。フォルダーを再選択してください。", recovery: .localAccess)
    }

    var currentName: String {
        guard let url = state.currentURL else { return "" }
        return displayNames[url] ?? url.lastPathComponent
    }

    func setPlaylist(_ files: [URL], displayNames: [URL: String] = [:], sizes: [URL: Int64] = [:]) {
        sessionRevision += 1
        discardPresentations()
        clearItem()
        self.displayNames = displayNames
        self.resourceSizes = sizes
        state.replace(files)
        needsFolderSelection = false
        pauseReason = nil
        failure = nil; showsFailure = false; confirmedSeconds = 0
    }

    func select(_ url: URL, autoplay: Bool? = nil) {
        guard !needsFolderSelection else { return }
        let wantsToPlay = autoplay ?? (state.currentURL == nil || state.ended || state.wantsToPlay)
        guard state.select(url) else { return }
        state.wantsToPlay = wantsToPlay && isActive && !interrupted && !isPresenting
        failure = nil; showsFailure = false; confirmedSeconds = 0
        loadCurrent()
    }

    func resume() {
        if failure != nil { retry(); return }
        guard isActive, !interrupted, !isPresenting, !needsFolderSelection, state.currentURL != nil else { return }
        if state.ended || player.currentItem == nil {
            let url = state.currentURL!
            select(url, autoplay: true)
        } else {
            state.wantsToPlay = true
            startPlayback()
        }
    }

    func pause() {
        confirmPosition()
        state.wantsToPlay = false
        // Preparation already keeps rate at zero; do not interrupt its preroll.
        if !isLoading { player.pause() }
        isBuffering = false
    }

    func move(_ offset: Int) {
        guard !isPresenting, !needsFolderSelection, state.move(offset) else { return }
        failure = nil; showsFailure = false; confirmedSeconds = 0
        loadCurrent()
    }

    func dismissFailure() { showsFailure = false }

    /// Explicit recovery preserves the queue and last confirmed position. Merely
    /// restoring a grant, returning to foreground or closing UI never calls this.
    func retry() {
        guard canRetry, let failure, failure.url == state.currentURL else { return }
        let seconds = failure.seconds
        self.failure = nil; showsFailure = false; needsFolderSelection = false
        state.wantsToPlay = true
        loadCurrent(resumingAt: seconds)
    }

    func nextAfterFailure() {
        guard failure != nil, !isPresenting, state.move(1) else { return }
        failure = nil; showsFailure = false; needsFolderSelection = false; confirmedSeconds = 0
        state.wantsToPlay = isActive && !interrupted
        loadCurrent()
    }

    func adjustVolume(by percentagePoints: Int) {
        volumePercent = min(100, max(0, volumePercent + percentagePoints))
        player.volume = Float(volumePercent) / 100
    }

    func seek(by seconds: Double) {
        guard canSeek, let item = player.currentItem, item.status == .readyToPlay else { return }
        refreshSeekability(item)
        let current = player.currentTime().seconds
        switch PlaybackSeekPolicy.action(current: current, by: seconds, duration: duration,
                                         ranges: seekableRanges, hasNext: state.canGoForward) {
        case .none: return
        case .next:
            move(1)
        case .position(let target):
            confirmPosition()
            seekRevision += 1
            let revision = seekRevision
            let token = generation
            isSeeking = true
            seekTask?.cancel()
            seekTask = Task { [weak self] in
                guard let self else { return }
                let finished = await self.performSeek(self.player, CMTime(seconds: target, preferredTimescale: 600))
                guard !Task.isCancelled, self.generation == token, self.seekRevision == revision else { return }
                self.isSeeking = false; self.seekTask = nil
                if finished { self.confirmPosition() }
                self.lastAdvance = .now
            }
        }
    }

    private func confirmPosition() {
        guard !isSeeking, !isLoading, failure == nil, player.currentItem?.status == .readyToPlay else { return }
        let seconds = player.currentTime().seconds
        if seconds.isFinite, seconds >= 0 { confirmedSeconds = seconds }
    }

    private func refreshSeekability(_ item: AVPlayerItem) {
        let seconds = item.duration.seconds
        duration = seconds.isFinite && seconds > 0 ? seconds : nil
        seekableRanges = PlaybackSeekPolicy.validRanges(item.seekableTimeRanges.compactMap {
            let range = $0.timeRangeValue
            let start = range.start.seconds, end = CMTimeRangeGetEnd(range).seconds
            guard start.isFinite, end.isFinite, start <= end else { return nil }
            return start...end
        })
    }

    private func clearItem(preservingInfo: Bool = false) {
        generation += 1
        seekRevision += 1; seekTask?.cancel(); seekTask = nil; isSeeking = false
        seekableRanges = []; duration = nil
        preparation?.cancel()
        preparation = nil
        player.cancelPendingPrerolls()
        player.currentItem?.cancelPendingSeeks()
        watchdog?.cancel()
        watchdog = nil
        isBuffering = false
        timeout?.cancel()
        timeout = nil
        statusObservation = nil
        rangeObservation = nil; durationObservation = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
        if let progressObserver { player.removeTimeObserver(progressObserver) }
        progressObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isLoading = false
        if !preservingInfo { mediaInfo = MediaInfo() }
    }

    private func loadCurrent(resumingAt seconds: Double = 0) {
        clearItem()
        confirmedSeconds = seconds
        guard let url = state.currentURL else { return }
        let item = AVPlayerItem(url: url)
        let token = generation
        isLoading = true
        mediaInfo = MediaInfo(name: currentName, size: "準備中", video: "準備中", audio: "準備中")
        logger.info("Preparing media for playback")
        lastProgress = 0
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                switch item.status {
                case .readyToPlay:
                    self.prepareCurrent(item, url: url, token: token, resumingAt: seconds)
                case .failed:
                    if url.isFileURL && Self.isAccessFailure(item.error) { self.accessFailed() }
                    else { self.recordFailure(item.error?.localizedDescription ?? "読み込めないファイルです。") }
                default: break
                }
            }
        }
        for name in [AVPlayerItem.didPlayToEndTimeNotification, AVPlayerItem.failedToPlayToEndTimeNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] notification in
                let failure = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
                let message = failure?.localizedDescription
                let accessFailure = Self.isAccessFailure(failure)
                let revision = MainActor.assumeIsolated { self?.presentationRevision }
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if name == AVPlayerItem.didPlayToEndTimeNotification {
                        guard !self.isPresenting, revision == self.presentationRevision else { return }
                        if self.state.move(1) { self.loadCurrent() }
                        else {
                            self.state.finish()
                            self.isBuffering = false
                            self.watchdog?.cancel()
                            self.player.pause()
                        }
                    } else if url.isFileURL && accessFailure { self.accessFailed() }
                    else { self.recordFailure(message ?? "再生中にエラーが発生しました。") }
                }
            })
        }
        player.replaceCurrentItem(with: item)
        rangeObservation = item.observe(\.seekableTimeRanges, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.refreshSeekability(item)
            }
        }
        durationObservation = item.observe(\.duration, options: [.new]) { [weak self] item, _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.refreshSeekability(item)
            }
        }
        progressObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                let seconds = time.seconds
                if seconds.isFinite, seconds > self.lastProgress, self.player.rate > 0 {
                    self.lastAdvance = .now
                    self.isBuffering = false
                }
                self.confirmPosition()
                self.refreshSeekability(item)
                self.lastProgress = seconds
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: self?.preparationLimit ?? .seconds(30)) } catch { return }
            guard let self, self.generation == token, self.isLoading else { return }
            self.recordFailure(url.isFileURL
                ? "読み込みが30秒以内に完了しませんでした。"
                : "読み込みが30秒以内に完了しませんでした。NASとネットワークの接続を確認してください。")
        }
        lastAdvance = .now
        watchdog = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
                guard let self, self.generation == token else { return }
                guard self.state.wantsToPlay, !self.isLoading, !self.state.ended else {
                    self.lastAdvance = .now
                    self.isBuffering = false
                    continue
                }
                let stalled = self.lastAdvance.duration(to: .now)
                self.checkStall(elapsed: stalled)
            }
        }
        if state.wantsToPlay { startPlayback() }
    }

    /// Finish metadata I/O and prime the decoder before advancing the playback clock.
    private func prepareCurrent(_ item: AVPlayerItem, url: URL, token: Int, resumingAt seconds: Double) {
        guard preparation == nil, isLoading else { return }
        preparation = Task { [weak self] in
            let info = await MediaInfo.load(url, asset: item.asset)
            guard let self, !Task.isCancelled, self.generation == token else { return }
            self.mediaInfo = info
            self.mediaInfo.name = self.currentName
            if let size = self.resourceSizes[url] {
                self.mediaInfo.size = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
            self.logger.info("Metadata ready; waiting for player readiness")
            // Item readiness and player readiness can be delivered in different callbacks.
            while self.player.status == .unknown {
                do { try await Task.sleep(for: .milliseconds(20)) } catch { return }
                guard self.generation == token else { return }
            }
            guard !Task.isCancelled, self.generation == token else { return }
            guard self.player.status == .readyToPlay else {
                self.recordFailure("再生の事前準備に失敗しました。")
                return
            }
            self.refreshSeekability(item)
            if seconds > 0 {
                guard self.seekableRanges.contains(where: { $0.contains(seconds) }) else {
                    self.recordFailure("最後に確認した位置へ移動できません。ファイルと接続を確認してください。")
                    return
                }
                self.isSeeking = true
                let finished = await self.performSeek(self.player, CMTime(seconds: seconds, preferredTimescale: 600))
                guard !Task.isCancelled, self.generation == token else { return }
                self.isSeeking = false
                guard finished else { self.recordFailure("再開位置への移動に失敗しました。"); return }
                let actual = self.player.currentTime().seconds
                guard actual.isFinite, abs(actual - seconds) < 1 else {
                    self.recordFailure("再開位置を確認できません。"); return
                }
                self.confirmedSeconds = actual
            }
            self.logger.info("Preroll started")
            let prepared = await self.player.preroll(atRate: 1)
            guard !Task.isCancelled, self.generation == token else { return }
            self.preparation = nil
            guard prepared else {
                self.recordFailure("再生データの事前読み込みに失敗しました。")
                return
            }
            self.isLoading = false
            self.refreshSeekability(item)
            self.lastAdvance = .now
            self.timeout?.cancel()
            self.logger.info("Preroll complete")
            if self.state.wantsToPlay { self.startPlayback() }
        }
    }

    // Shared by the monotonic watchdog and deterministic state-transition tests.
    func checkStall(elapsed: Duration) {
        guard state.wantsToPlay, !isLoading, !state.ended else {
            isBuffering = false
            return
        }
        if !isBuffering, elapsed >= .seconds(2) { logger.notice("Playback stopped advancing for at least two seconds") }
        isBuffering = elapsed >= .seconds(2)
        if elapsed >= .seconds(30) {
            recordFailure(state.currentURL?.isFileURL == false
                ? "再生が30秒間進みませんでした。NASとネットワークの接続を確認してください。"
                : "再生が30秒間進みませんでした。外部ストレージの接続も確認してください。")
        }
    }

    private func recordFailure(_ message: String, recovery: PlaybackFailure.Recovery? = nil) {
        guard failure == nil, let url = state.currentURL else { return }
        confirmPosition()
        let kind = recovery ?? (url.isFileURL ? .media : .network)
        failure = PlaybackFailure(url: url, name: currentName, reason: message,
                                  seconds: confirmedSeconds, recovery: kind)
        state.failed()
        needsFolderSelection = kind == .localAccess
        showsFailure = true
        clearItem(preservingInfo: true)
        mediaInfo.name = currentName
        if mediaInfo.size == "準備中" { mediaInfo.size = "取得できません" }
        if mediaInfo.video == "準備中" { mediaInfo.video = "取得できません" }
        if mediaInfo.audio == "準備中" { mediaInfo.audio = "取得できません" }
    }

    isolated deinit {
        seekTask?.cancel()
        preparation?.cancel()
        player.cancelPendingPrerolls()
        watchdog?.cancel()
        systemNotifications.forEach { NotificationCenter.default.removeObserver($0) }
        timeout?.cancel()
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        if let progressObserver { player.removeTimeObserver(progressObserver) }
    }
}
