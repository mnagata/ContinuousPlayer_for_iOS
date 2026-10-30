import SwiftUI
import AVFoundation

struct MediaInfoSheet: View {
    let info: MediaInfo
    let folderName: String
    @Environment(\.dismiss) private var dismiss
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
            .textSelection(.enabled)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Text("キーボード: I または Esc で閉じる")
                    .font(.caption).foregroundStyle(.secondary).padding(8)
            }
            .background(ModalDismissKeyboardCommands { dismiss() })
            #else
            .onExitCommand { dismiss() }
            .safeAreaInset(edge: .bottom) {
                Button("閉じる") { dismiss() }.accessibilityIdentifier("player.info.close").padding()
            }
            #endif
            .navigationTitle("メディア情報")
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("閉じる") { dismiss() }.accessibilityIdentifier("player.info.close")
                }
            }
            #endif
        }
        .onAppear { output = .current() }
        .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { _ in output = .current() }
    }
}
