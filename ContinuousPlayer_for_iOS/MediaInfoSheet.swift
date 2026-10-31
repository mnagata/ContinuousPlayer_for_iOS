import SwiftUI
import AVFoundation

struct MediaInfoSheet: View {
    let info: MediaInfo
    let folderName: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.self) private var environment

    var body: some View {
        #if os(tvOS)
        MediaInformationContent(info: info, folderName: folderName, close: { dismiss() })
        #else
        InformationKeyboardHost(
            content: MediaInformationContent(info: info, folderName: folderName, close: { dismiss() })
                .environment(\.self, environment),
            close: { dismiss() })
        #endif
    }
}

private struct MediaInformationContent: View {
    let info: MediaInfo
    let folderName: String
    let close: () -> Void
    @FocusState private var closeFocused: Bool
    @FocusState private var informationFocused: Bool
    @State private var output = AudioOutputInfo()
    var body: some View {
        NavigationStack {
            List {
                Section("ファイル") {
                    LabeledContent("名前", value: info.name)
                    LabeledContent("フォルダー", value: folderName)
                    LabeledContent("サイズ", value: info.size)
                }
                Section("映像・音声形式") {
                    LabeledContent("映像", value: info.video)
                    LabeledContent("音声", value: info.audio)
                }
                Section("音声出力") {
                    LabeledContent("デバイス", value: output.device)
                    LabeledContent("実際の出力設定", value: output.configuration)
                    Text("出力設定はAVAudioSessionの現在値です。ビットパーフェクトを保証するものではありません。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            #if !os(tvOS)
            .focusable(interactions: .edit).focused($informationFocused)
            .textSelection(.enabled)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Text("キーボード: I または Esc で閉じる")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
            }
            #else
            .onExitCommand { close() }
            .safeAreaInset(edge: .bottom) {
                Button("閉じる") { close() }.keyboardAction { close() }.focused($closeFocused).accessibilityIdentifier("player.info.close").padding()
            }
            #endif
            .navigationTitle("メディア情報")
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { close() }
                        .keyboardAction { close() }
                        .focused($closeFocused)
                        .accessibilityIdentifier("player.info.close")
                }
            }
            #endif
        }
        .onAppear { output = .current() }
        .task {
            #if os(tvOS)
            closeFocused = true
            #else
            informationFocused = true
            #endif
        }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in output = .current() }
    }
}
