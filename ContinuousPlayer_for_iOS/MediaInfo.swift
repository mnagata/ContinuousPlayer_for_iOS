import AVFoundation

struct MediaInfo {
    var name = ""
    var size = "取得できません"
    var video = "取得できません"
    var audio = "取得できません"

    static func load(_ url: URL, asset: AVAsset) async -> MediaInfo {
        var info = MediaInfo(name: url.lastPathComponent)
        let bytes = await Task.detached(priority: .utility) {
            url.isFileURL ? try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize : nil
        }.value
        guard !Task.isCancelled else { return info }
        if let bytes {
            info.size = ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
        }
        do {
            if let track = try await asset.loadTracks(withMediaType: .video).first {
                let size = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let display = size.applying(transform)
                let fps = try await track.load(.nominalFrameRate)
                let formats = try await track.load(.formatDescriptions)
                let resolution = display.width.isFinite && display.height.isFinite && abs(display.width) > 0 && abs(display.height) > 0
                    ? "\(Int(abs(display.width))) × \(Int(abs(display.height)))" : "解像度: 取得できません"
                let frameRate = fps.isFinite && fps > 0 ? "\(String(format: "%.2f", fps)) fps" : "fps: 取得できません"
                info.video = "\(formats.first.map(codec) ?? "取得できません") · \(resolution) · \(frameRate)"
            } else { info.video = "映像なし" }
        } catch { /* A video failure must not hide independently available audio. */ }
        guard !Task.isCancelled else { return info }
        do {
            if let track = try await asset.loadTracks(withMediaType: .audio).first {
                let formats = try await track.load(.formatDescriptions)
                if let format = formats.first {
                    info.audio = codec(format)
                    if let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                        let rate = stream.mSampleRate.isFinite && stream.mSampleRate > 0
                            ? "\(String(format: "%.1f", stream.mSampleRate / 1000)) kHz" : "サンプルレート: 取得できません"
                        let channels = stream.mChannelsPerFrame > 0 ? "\(stream.mChannelsPerFrame) ch" : "チャンネル数: 取得できません"
                        info.audio += " · \(rate) · \(channels)"
                    }
                }
            } else { info.audio = "音声なし" }
        } catch { /* Keep independently available file information. */ }
        return info
    }

    private static func codec(_ format: CMFormatDescription) -> String {
        let code = CMFormatDescriptionGetMediaSubType(format)
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 255) }
        let value = String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces)
        return value.flatMap { $0.isEmpty ? nil : $0 } ?? "取得できません"
    }
}

/// Unavailable data and an API absent from this build are different states.
struct AudioOutputInfo {
    var device = "取得できません"
    var configuration = "取得できません"
    static func current() -> AudioOutputInfo {
        #if os(iOS) || os(tvOS)
        let session = AVAudioSession.sharedInstance()
        let devices = session.currentRoute.outputs.map(\.portName).filter { !$0.isEmpty }
        let rate = session.sampleRate
        let channels = session.outputNumberOfChannels
        return AudioOutputInfo(device: devices.isEmpty ? "取得できません" : devices.joined(separator: ", "),
            configuration: rate.isFinite && rate > 0 && channels > 0
                ? "\(String(format: "%.1f", rate / 1000)) kHz · \(channels) ch" : "取得できません")
        #else
        return AudioOutputInfo(device: "未対応", configuration: "未対応")
        #endif
    }
}
