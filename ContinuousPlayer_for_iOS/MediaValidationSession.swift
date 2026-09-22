import AVFoundation
import Observation
import UIKit

@MainActor @Observable
final class MediaValidationSession {
    let player = AVPlayer()
    var files: [URL] = []
    var folderName = "未選択"
    var currentName = ""
    var busy = false
    var error: String?
    var report = ""
    private var scopedURL: URL?
    let playback = PlaybackController()
    private var started = false
    private let bookmarkKey = "validation.folder.bookmark"
    private var reportURL: URL { URL.documentsDirectory.appendingPathComponent("validation-log.txt") }

    func start() {
        guard !started else { return }
        started = true
        report = (try? String(contentsOf: reportURL, encoding: .utf8)) ?? ""
        record("起動: \(UIDevice.current.model), \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        if ProcessInfo.processInfo.arguments.contains("--validate-fixtures") { useFixtures() }
        if ProcessInfo.processInfo.arguments.contains("--validate-real-samples") { useRealSamples() }
    }

    func record(_ message: String) {
        let line = "\(Date().ISO8601Format()) \(message)"
        report += line + "\n"
        print(line)
        do { try report.write(to: reportURL, atomically: true, encoding: .utf8) }
        catch { self.error = "ログ保存失敗: \(error.localizedDescription)" }
    }

    func restore() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else {
            error = "保存済みフォルダーがありません。フォルダーを選択してください。"
            return
        }
        do {
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            record("ブックマーク解決: stale=\(stale)")
            open(url, persist: true)
        } catch { fail(error) }
    }

    func useFixtures() {
        open(URL.documentsDirectory.appendingPathComponent("ValidationFixtures"), persist: false, validate: true)
    }

    func useRealSamples() {
        open(URL.documentsDirectory.appendingPathComponent("RealSamples"), persist: false, validate: true)
    }

    func open(_ url: URL, persist: Bool, validate: Bool = false) {
        guard !busy else { return }
        player.pause()
        player.replaceCurrentItem(with: nil)
        playback.setPlaylist([])
        currentName = ""
        if let scopedURL { scopedURL.stopAccessingSecurityScopedResource() }
        scopedURL = url.startAccessingSecurityScopedResource() ? url : nil
        files = []
        error = nil
        folderName = url.lastPathComponent
        busy = true
        Task {
            defer { busy = false; currentName = "" }
            do {
                files = try await MediaScanner.scan(url)
                record("列挙・OP/ED整列: \(folderName), 対象=\(files.count), securityScope=\(scopedURL != nil)")
                if persist {
                    let data = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                    UserDefaults.standard.set(data, forKey: bookmarkKey)
                    record("ブックマーク保存成功")
                }
                if !validate { playback.setPlaylist(files) }
                if validate {
                    for file in files { await inspect(file) }
                    record("検証完了（映像・音声の目視／聴取は別途必要）")
                }
            } catch { fail(error) }
        }
    }

    private func inspect(_ url: URL) async {
        let asset = AVURLAsset(url: url)
        let timeout = Task {
            try? await Task.sleep(for: .seconds(15))
            if !Task.isCancelled { asset.cancelLoading() }
        }
        defer { timeout.cancel(); player.pause(); player.replaceCurrentItem(with: nil) }
        do {
            let playable = try await asset.load(.isPlayable)
            let duration = try await asset.load(.duration).seconds
            let tracks = try await asset.load(.tracks)
            var codecs: [String] = []
            for track in tracks {
                for format in try await track.load(.formatDescriptions) {
                    let code = CMFormatDescriptionGetMediaSubType(format)
                    let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 255) }
                    codecs.append(String(bytes: bytes, encoding: .ascii) ?? "\(code)")
                }
            }
            record("素材: \(url.lastPathComponent), isPlayable=\(playable), duration=\(duration), codecs=\(codecs)")
            guard playable else { return }
            let item = AVPlayerItem(asset: asset)
            let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: nil)
            let hasVideo = tracks.contains { $0.mediaType == .video }
            if hasVideo { item.add(videoOutput) }
            player.replaceCurrentItem(with: item)
            currentName = url.lastPathComponent
            let deadline = Date().addingTimeInterval(15)
            while item.status == .unknown && Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
            guard item.status == .readyToPlay else {
                record("準備失敗/タイムアウト: \(currentName): \(String(describing: item.error))")
                return
            }
            player.play()
            try await Task.sleep(for: .seconds(2))
            let progressed = player.currentTime().seconds
            player.pause()
            record("再生計測: \(currentName), elapsed=\(progressed), status=\(item.status.rawValue), error=\(String(describing: item.error))")
            if hasVideo {
                let frame = videoOutput.copyPixelBuffer(forItemTime: player.currentTime(), itemTimeForDisplay: nil)
                record("映像デコード計測: \(currentName), pixelBuffer=\(frame != nil)")
            }
            if duration.isFinite && duration > 2 {
                let target = min(duration / 2, 10)
                player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero, completionHandler: { _ in })
                let seekDeadline = Date().addingTimeInterval(5)
                while abs(player.currentTime().seconds - target) > 0.15 && Date() < seekDeadline {
                    try await Task.sleep(for: .milliseconds(100))
                }
                let actual = player.currentTime().seconds
                record("シーク計測: \(currentName), reached=\(actual.isFinite && abs(actual - target) <= 0.15), target=\(target), actual=\(actual)")
            }
        } catch { record("素材エラー: \(url.lastPathComponent): \(error as NSError)") }
    }

    private func fail(_ error: Error) {
        playback.accessFailed()
        self.error = "\(error.localizedDescription) フォルダーを再選択してください。"
        record("アクセスエラー: \(error as NSError)")
    }
}
