import SwiftUI
import AVKit
import UniformTypeIdentifiers

struct ValidationView: View {
    @State private var probe = MediaValidationSession()
    @State private var choosingFolder = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                Section("ファイル・形式の実機検証") {
                    Text("検証用画面です。APIの判定と映像・音声の確認結果を分けて記録します。")
                    Button("フォルダーを選択") { choosingFolder = true }
                    Button("保存したフォルダーを復元") { probe.restore() }
                    Button("合成サンプルを検証") { probe.useFixtures() }
                    Button("実素材サンプルを検証") { probe.useRealSamples() }
                    Text(probe.folderName)
                    if probe.busy { ProgressView("読み込み・検証中") }
                    if let error = probe.error { Text(error).foregroundStyle(.red) }
                }.disabled(probe.busy)
                Section("再生確認") {
                    PlaybackSurface(player: probe.busy ? probe.player : probe.playback.player).frame(height: 240)
                    Text(probe.busy ? probe.currentName : probe.playback.currentName)
                    HStack {
                        Button("再生") { probe.playback.resume() }
                        Button("一時停止") { probe.playback.pause() }
                        Button("−10秒") { probe.playback.seek(by: -10) }
                        Button("+10秒") { probe.playback.seek(by: 10) }
                    }.disabled(probe.busy)
                    HStack {
                        Button("前へ") { probe.playback.move(-1) }.disabled(!probe.playback.state.canGoBack)
                        Button("次へ") { probe.playback.move(1) }.disabled(!probe.playback.state.canGoForward)
                    }.disabled(probe.busy)
                    if probe.playback.isLoading { ProgressView("再生準備中") }
                    if probe.playback.isBuffering { ProgressView("バッファリング中") }
                    if let reason = probe.playback.pauseReason { Text(reason).foregroundStyle(.secondary) }
                    if probe.playback.state.ended { Text("プレイリストの再生が終了しました") }
                    if let error = probe.playback.error { Text(error).foregroundStyle(.red) }
                    HStack {
                        Button("映像・音声を確認済み") { probe.record("手動確認: 映像・音声を確認済み: \(probe.playback.currentName)") }
                        Button("再生に問題あり") { probe.record("手動確認: 再生に問題あり: \(probe.playback.currentName)") }
                    }.disabled(probe.playback.currentName.isEmpty || probe.busy)
                }
                Section("列挙結果（直下のみ・OP/ED順）") {
                    if probe.files.isEmpty && !probe.busy { Text("対象ファイルがありません").foregroundStyle(.secondary) }
                    ForEach(probe.files, id: \.self) { url in
                        Button(url.lastPathComponent) { probe.playback.select(url) }.disabled(probe.busy)
                    }
                }
                Section("記録") {
                    ShareLink("検証ログを共有", item: probe.report)
                    Text(probe.report).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            .buttonStyle(.borderless)
            .navigationTitle("ContinuousPlayer 検証")
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                switch result {
                case .success(let url): probe.open(url, persist: true)
                case .failure(let error): probe.error = error.localizedDescription
                }
            }
            .task { probe.playback.setActive(scenePhase == .active); probe.start() }
            .onChange(of: scenePhase) { _, phase in
                probe.playback.setActive(phase == .active)
                if phase != .active {
                    probe.player.pause()

                }
            }
        }
    }
}
