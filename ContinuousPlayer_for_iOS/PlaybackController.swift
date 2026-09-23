import AVFoundation
import Observation
import OSLog

@MainActor @Observable
final class PlaybackController {
    private(set) var player = AVPlayer()
    private(set) var state = PlaybackState()
    private(set) var volumePercent = 100
    private(set) var error: String?
    private(set) var isLoading = false
    private(set) var mediaInfo = MediaInfo()
    private var displayNames: [URL: String] = [:]
    private var resourceSizes: [URL: Int64] = [:]
    private var preparation: Task<Void, Never>?
    private let logger = Logger(subsystem: "jp.nagu.ContinuousPlayer-for-iOS", category: "PlaybackStartup")
    private var statusObservation: NSKeyValueObservation?
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
    private(set) var pauseReason: String?
    private(set) var needsFolderSelection = false
    private(set) var isBuffering = false
    var showsPauseControls: Bool {
        state.currentURL != nil && !state.wantsToPlay && !state.ended && !needsFolderSelection
    }

    init() {
        #if os(iOS)
        let center = NotificationCenter.default
        systemNotifications.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
            Task { @MainActor [weak self] in self?.setInterrupted(began) }
        })
        systemNotifications.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard (notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            Task { @MainActor [weak self] in self?.outputDisconnected() }
        })
        systemNotifications.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
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
        isActive = active
        if !active {
            pause()
            pauseReason = "アプリが非アクティブになったため停止しました。"
        }
    }

    func setInterrupted(_ value: Bool) {
        interrupted = value
        if value {
            pause()
            pauseReason = "音声の割り込みで停止しました。割り込み終了後、手動で再開してください。"
        }
    }

    func outputDisconnected() {
        pause()
        pauseReason = "音声出力機器が切断されました。再生ボタンで再開できます。"
    }

    private func startPlayback() {
        guard isActive, !interrupted, !needsFolderSelection else {
            state.wantsToPlay = false
            return
        }
        guard !isLoading, state.wantsToPlay else { return }
        #if os(iOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            pause()
            self.error = "音声出力を開始できません: \(error.localizedDescription)"
            return
        }
        #endif
        pauseReason = nil
        lastAdvance = .now
        player.play()
    }

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
        pause()
        clearItem()
        needsFolderSelection = true
        error = "フォルダーへのアクセスが失われました。フォルダーを再選択してください。"
    }

    var currentName: String {
        guard let url = state.currentURL else { return "" }
        return displayNames[url] ?? url.lastPathComponent
    }

    func setPlaylist(_ files: [URL], displayNames: [URL: String] = [:], sizes: [URL: Int64] = [:]) {
        clearItem()
        self.displayNames = displayNames
        self.resourceSizes = sizes
        state.replace(files)
        needsFolderSelection = false
        pauseReason = nil
        error = nil
    }

    func select(_ url: URL, autoplay: Bool? = nil) {
        guard !needsFolderSelection else { return }
        let wantsToPlay = autoplay ?? (state.currentURL == nil || state.ended || state.wantsToPlay)
        guard state.select(url) else { return }
        state.wantsToPlay = wantsToPlay
        error = nil
        loadCurrent()
    }

    func resume() {
        guard isActive, !interrupted, !needsFolderSelection, state.currentURL != nil else { return }
        if state.ended || player.currentItem == nil {
            let url = state.currentURL!
            select(url, autoplay: true)
        } else {
            state.wantsToPlay = true
            startPlayback()
        }
    }

    func pause() {
        state.wantsToPlay = false
        // Preparation already keeps rate at zero; do not interrupt its preroll.
        if !isLoading { player.pause() }
        isBuffering = false
    }

    func move(_ offset: Int) {
        guard !needsFolderSelection, state.move(offset) else { return }
        error = nil
        loadCurrent()
    }

    func adjustVolume(by percentagePoints: Int) {
        volumePercent = min(100, max(0, volumePercent + percentagePoints))
        player.volume = Float(volumePercent) / 100
    }

    func seek(by seconds: Double) {
        guard !isLoading, let item = player.currentItem, item.status == .readyToPlay else { return }
        let current = player.currentTime().seconds
        let duration = item.duration.seconds
        guard current.isFinite, duration.isFinite, duration > 0 else { return }
        let target = max(0, current + seconds)
        if target >= duration {
            move(1)
        } else {
            player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        }
    }

    private func clearItem() {
        generation += 1
        preparation?.cancel()
        preparation = nil
        player.cancelPendingPrerolls()
        watchdog?.cancel()
        watchdog = nil
        isBuffering = false
        timeout?.cancel()
        timeout = nil
        statusObservation = nil
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        notifications.removeAll()
        if let progressObserver { player.removeTimeObserver(progressObserver) }
        progressObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isLoading = false
        mediaInfo = MediaInfo()
    }

    private func loadCurrent() {
        clearItem()
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
                    self.prepareCurrent(item, url: url, token: token)
                case .failed:
                    if url.isFileURL && Self.isAccessFailure(item.error) { self.accessFailed() }
                    else { self.handleFailure(item.error?.localizedDescription ?? "読み込めないファイルです。") }
                default: break
                }
            }
        }
        for name in [AVPlayerItem.didPlayToEndTimeNotification, AVPlayerItem.failedToPlayToEndTimeNotification] {
            notifications.append(NotificationCenter.default.addObserver(forName: name, object: item, queue: .main) { [weak self] notification in
                let failure = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? NSError
                let message = failure?.localizedDescription
                let accessFailure = Self.isAccessFailure(failure)
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    if name == AVPlayerItem.didPlayToEndTimeNotification {
                        if self.state.move(1) { self.loadCurrent() }
                        else {
                            self.state.finish()
                            self.isBuffering = false
                            self.watchdog?.cancel()
                            self.player.pause()
                        }
                    } else if url.isFileURL && accessFailure { self.accessFailed() }
                    else { self.handleFailure(message ?? "再生中にエラーが発生しました。") }
                }
            })
        }
        player.replaceCurrentItem(with: item)
        progressObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600), queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                guard let self, self.generation == token else { return }
                let seconds = time.seconds
                if seconds.isFinite, seconds > self.lastProgress, self.player.rate > 0 {
                    self.lastAdvance = .now
                    self.isBuffering = false
                    self.state.didProgress()
                    self.error = nil
                }
                self.lastProgress = seconds
            }
        }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.generation == token, self.isLoading else { return }
            self.handleFailure(url.isFileURL
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
    private func prepareCurrent(_ item: AVPlayerItem, url: URL, token: Int) {
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
                self.handleFailure("再生の事前準備に失敗しました。")
                return
            }
            self.logger.info("Preroll started")
            let prepared = await self.player.preroll(atRate: 1)
            guard !Task.isCancelled, self.generation == token else { return }
            self.preparation = nil
            guard prepared else {
                self.handleFailure("再生データの事前読み込みに失敗しました。")
                return
            }
            self.isLoading = false
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
            handleFailure(state.currentURL?.isFileURL == false
                ? "再生が30秒間進みませんでした。NASとネットワークの接続を確認してください。"
                : "再生が30秒間進みませんでした。外部ストレージの接続も確認してください。")
        }
    }

    private func handleFailure(_ message: String) {
        let name = currentName
        let shouldContinue = state.failed()
        error = "\(name): \(message)"
        if shouldContinue { loadCurrent() }
        else { clearItem() }
    }

    isolated deinit {
        preparation?.cancel()
        player.cancelPendingPrerolls()
        watchdog?.cancel()
        systemNotifications.forEach { NotificationCenter.default.removeObserver($0) }
        timeout?.cancel()
        notifications.forEach { NotificationCenter.default.removeObserver($0) }
        if let progressObserver { player.removeTimeObserver(progressObserver) }
    }
}
