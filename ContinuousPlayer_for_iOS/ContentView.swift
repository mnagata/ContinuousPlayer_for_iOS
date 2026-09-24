import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ContentView: View {
    @State private var library = MediaLibrary()
    @AppStorage("useSystemFilePicker") private var useSystemFilePicker = false
    @AppStorage("isDLNAEnabled") private var isDLNAEnabled = true
    private enum Presentation: String, Identifiable {
        case folder, file, browser, player, dlna
        var id: String { rawValue }
    }
    @State private var presentation: Presentation?
    @State private var pickedURL: URL?
    @State private var lastPlaybackURL: URL?
    @State private var pickedFile = false
    @State private var pickerHasDismissed = false
    @State private var showingLibrary = false
    @State private var pickFolderAfterPlayback = false
    @State private var pickerError: String?
    @State private var authorizationStatus: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            HomeView(authorizationStatus: authorizationStatus,
                     isDLNAEnabled: isDLNAEnabled, authorize: beginAuthorization, selectDLNA: {
                if isDLNAEnabled { presentation = .dlna }
            }) {
                Task {
                    await beginSelection()
                }
            }
            .overlay {
                if library.isLoading { ProgressView("プレイリストを作成中…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
            .disabled(library.isLoading)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView(useSystemFilePicker: $useSystemFilePicker, isDLNAEnabled: $isDLNAEnabled)
                    } label: {
                        Label("設定", systemImage: "gearshape")
                            .foregroundStyle(.white)
                    }
                    .tint(.white)
                    .accessibilityIdentifier("home.settings")
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.06, green: 0.09, blue: 0.26), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(isPresented: $showingLibrary) {
                PlaylistView(library: library, chooseFolder: beginAuthorization) { url in
                    library.playback.select(url, autoplay: false)
                    presentation = .player
                }
            }
        }
        .tint(.cyan)
        .alert("メディアを開けません", isPresented: Binding(get: { pickerError != nil }, set: { if !$0 { pickerError = nil } })) {
            Button("閉じる", role: .cancel) { pickerError = nil }
        } message: { Text(pickerError ?? "") }
        // One presenter serializes folder -> player -> folder transitions.
        .fullScreenCover(item: $presentation, onDismiss: presentationDidDismiss) { destination in
            switch destination {
            case .folder, .file:
                VStack(spacing: 0) {
                    HStack {
                        Button("キャンセル", role: .cancel) {
                            pickedURL = nil
                            presentation = nil
                        }
                        .accessibilityIdentifier("folder.cancel")
                        .frame(minHeight: 44)
                        Spacer()
                    }
                    .padding(.horizontal)
                    Text(destination == .folder
                         ? "アクセスを許可するUSB内のフォルダーを開いて、右上の「開く」を押してください。"
                         : "再生を開始する動画・音声ファイルをタップしてください。")
                        .accessibilityIdentifier(destination == .file ? "picker.filePrompt" : "picker.folderPrompt")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    SystemMediaPicker(folder: destination == .folder,
                                      directory: destination == .file ? library.currentDirectoryURL : library.folderURL) { url in
                        pickedFile = destination == .file
                        pickedURL = url
                        presentation = nil
                        finishFolderSelectionIfReady()
                    }
                    .id(destination)
                }
            case .browser:
                if let root = library.folderURL {
                    MediaFileBrowser(root: root, initialDirectory: library.currentDirectoryURL ?? root,
                                     initialFile: lastPlaybackURL) { url in
                        pickedFile = true
                        pickedURL = url
                        presentation = nil
                        finishFolderSelectionIfReady()
                    }
                }
            case .dlna:
                DLNABrowser()
            case .player:
                PlayerScreen(playback: library.playback, folderName: library.folderName) {
                    lastPlaybackURL = library.playback.state.currentURL
                    library.stop()
                    presentation = nil
                    showingLibrary = false
                } chooseFolder: {
                    pickFolderAfterPlayback = true
                    lastPlaybackURL = library.playback.state.currentURL
                    library.stop()
                    presentation = nil
                    showingLibrary = false
                }
            }
        }
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-fixtures") || arguments.contains("--ui-real-samples") {
                showingLibrary = true
                let folder = arguments.contains("--ui-real-samples") ? "RealSamples"
                    : arguments.contains("--ui-narrow-folder") ? "UIFixtures/SecondPlaylist" : "UIFixtures"
                await library.open(URL.documentsDirectory.appendingPathComponent(folder), persist: false)
                return
            }
            #endif
            if library.hasSavedFolder {
                await library.restore(loadPlaylist: false)
                authorizationStatus = library.error == nil
                    ? "許可済み: \(library.folderName)" : "保存したアクセス許可を復元できません。再度許可してください。"
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in library.playback.setActive(phase == .active) }
    }

    private func presentationDidDismiss() {
        if pickFolderAfterPlayback {
            pickFolderAfterPlayback = false
            Task { await beginSelection() }
        } else {
            pickerHasDismissed = true
            finishFolderSelectionIfReady()
        }
    }

    // UIKit can deliver the selected URL after SwiftUI's dismissal callback.
    // Wait for both events, whichever arrives first, and consume the URL once.
    private func finishFolderSelectionIfReady() {
        guard pickerHasDismissed, let url = pickedURL else { return }
        pickedURL = nil
        pickerHasDismissed = false
        let isFile = pickedFile
        Task {
            if isFile {
                await library.playFromSelection(url, autoplay: false)
                showPlaybackOrError()
            } else {
                await library.authorizeFolder(url)
                if let error = library.error {
                    pickerError = error
                } else {
                    showingLibrary = false
                    authorizationStatus = "アクセス許可を保存しました: \(library.folderName)"
                }
            }
        }
    }

    private func beginAuthorization() {
        lastPlaybackURL = nil
        pickerHasDismissed = false
        pickedURL = nil
        presentation = .folder
    }

    private func beginSelection() async {
        let canSelectFile = await library.prepareFileSelection()
        guard canSelectFile else {
            pickerError = "先に「USBストレージへのアクセスを許可」で、再生するファイルのあるフォルダーを許可してください。"
            return
        }
        pickerHasDismissed = false
        pickedURL = nil
        presentation = useSystemFilePicker ? .file : .browser
    }

    private func showPlaybackOrError() {
        if library.error == nil {
            showingLibrary = false
            presentation = .player
        } else {
            pickerError = library.error
        }
    }

}

private struct HomeView: View {
    let authorizationStatus: String?
    let isDLNAEnabled: Bool
    let authorize: () -> Void
    let selectDLNA: () -> Void
    let select: () -> Void
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Image("PlayerMark")
                        .resizable().scaledToFit()
                        .frame(width: geometry.size.height < 450 ? 120 : 200)
                        .accessibilityHidden(true)
                    VStack(spacing: 12) {
                        Text("ANIME OPENINGS / ENDINGS")
                            .font(.caption.weight(.semibold)).tracking(3).foregroundStyle(.cyan)
                        Text("ContinuousPlayer")
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    Button(action: authorize) {
                        Label("USBストレージへのアクセスを許可", systemImage: "externaldrive.badge.checkmark")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered).frame(maxWidth: 360)
                    .accessibilityIdentifier("home.authorizeFolder")
                    if let authorizationStatus {
                        Text(authorizationStatus).font(.caption).multilineTextAlignment(.center)
                            .accessibilityIdentifier("home.authorizationStatus")
                    }
                    Button(action: select) {
                        Label("OP / EDを選ぶ", systemImage: "folder")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(LinearGradient(colors: [.teal, .indigo], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain).frame(maxWidth: 320)
                    .accessibilityIdentifier("home.select")
                    if isDLNAEnabled {
                        Button(action: selectDLNA) {
                            Label("DLNAサーバーから選ぶ", systemImage: "network")
                                .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                        }
                        .buttonStyle(.bordered).frame(maxWidth: 360)
                        .accessibilityIdentifier("home.selectDLNA")
                    }
                    Text("USB再生では最初にストレージへのアクセスを許可してください。\n保存した許可は次回も使用します。")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .foregroundStyle(.white)
        .background(HomeAppearance.background.ignoresSafeArea())
    }
}

private struct SettingsView: View {
    @Binding var useSystemFilePicker: Bool
    @Binding var isDLNAEnabled: Bool

    var body: some View {
        Form {
            Section {
                Toggle("DLNA機能を使う", isOn: $isDLNAEnabled)
                    .accessibilityIdentifier("settings.isDLNAEnabled")
            } header: {
                Text("DLNA")
            } footer: {
                Text("オンにすると、ホームに「DLNAサーバーから選ぶ」が表示されます。")
            }
            Section {
                Toggle("標準ファイルダイアログを使う", isOn: $useSystemFilePicker)
                    .accessibilityIdentifier("settings.useSystemFilePicker")
            } header: {
                Text("USBストレージのファイル選択")
            } footer: {
                Text("オフ：検索窓のないアプリ内一覧を使います。\nオン：標準ファイルダイアログを使います。")
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PlaylistView: View {
    let library: MediaLibrary
    let chooseFolder: () -> Void
    let select: (URL) -> Void

    var body: some View {
        List {
            Section {
                Label(library.folderName.isEmpty ? "フォルダー未選択" : library.folderName, systemImage: "folder.fill")
                Button("フォルダーを選び直す", action: chooseFolder)
                    .disabled(library.isLoading)
            }
            if library.isLoading {
                ProgressView("ファイルを読み込み中…")
            } else if let error = library.error {
                ContentUnavailableView("フォルダーを開けません", systemImage: "folder.badge.questionmark", description: Text(error))
            } else if library.files.isEmpty {
                ContentUnavailableView("対象ファイルがありません", systemImage: "music.note.list", description: Text("動画・音声ファイルのあるフォルダーを選んでください。サブフォルダーは検索しません。"))
            } else {
                Section {
                    ForEach(Array(library.files.enumerated()), id: \.element) { index, url in
                        Button { select(url) } label: {
                            HStack(spacing: 14) {
                                Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 24)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(url.deletingPathExtension().lastPathComponent).foregroundStyle(.primary)
                                    Text(url.pathExtension.uppercased()).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "play.circle.fill").font(.title2)
                            }.padding(.vertical, 5).contentShape(Rectangle())
                        }
                        .accessibilityLabel("\(index + 1)、\(url.lastPathComponent)から再生")
                    }
                } header: { Text("\(library.files.count)件 · OP / ED順") }
                footer: { Text("選んだファイルから順に、最後まで連続再生します。") }
            }
        }
        .navigationTitle("OP / EDを選ぶ")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("ホーム") { ContentView() }
#Preview("空の一覧") {
    NavigationStack { PlaylistView(library: MediaLibrary(), chooseFolder: {}, select: { _ in }) }
}

/// Uses the same system picker for folder grants and permitted start-file selection.
private struct SystemMediaPicker: UIViewControllerRepresentable {
    let folder: Bool
    let directory: URL?
    let completion: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        // Providers can report supported media as generic data instead of its extension's UTI.
        // Validate the selected extension in MediaLibrary, rather than disabling the row here.
        let types: [UTType] = folder ? [.folder] : [.data]
        let controller = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
        controller.title = folder ? "USBストレージへのアクセスを許可" : "開始ファイルを選ぶ"
        controller.directoryURL = directory
        controller.allowsMultipleSelection = false
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {
        context.coordinator.completion = completion
    }
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}
