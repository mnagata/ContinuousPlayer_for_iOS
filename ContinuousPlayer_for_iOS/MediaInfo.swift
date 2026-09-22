import AVFoundation

struct MediaInfo {
    var name = ""
    var size = "取得できません"
    var video = "映像なし／取得できません"
    var audio = "取得できません"

    static func load(_ url: URL, asset: AVAsset) async -> MediaInfo {
        var info = MediaInfo(name: url.lastPathComponent)
        let bytes = await Task.detached(priority: .utility) {
            try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
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
                info.video = "\(formats.first.map(codec) ?? "不明") · \(Int(abs(display.width))) × \(Int(abs(display.height))) · \(String(format: "%.2f", fps)) fps"
            }
            try Task.checkCancellation()
            if let track = try await asset.loadTracks(withMediaType: .audio).first {
                let formats = try await track.load(.formatDescriptions)
                if let format = formats.first {
                    info.audio = codec(format)
                    if let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                        info.audio += " · \(String(format: "%.1f", stream.mSampleRate / 1000)) kHz · \(stream.mChannelsPerFrame) ch"
                    }
                }
            }
        } catch { /* Keep independently available file information. */ }
        return info
    }

    private static func codec(_ format: CMFormatDescription) -> String {
        let code = CMFormatDescriptionGetMediaSubType(format)
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 255) }
        return String(bytes: bytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? "不明"
    }
}
