import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import UIKit
import OSLog

private enum FolderAction {
    case local(RegisteredLocalFolder), dlna(RegisteredDLNAFolder), addLocal, addDLNA
}

struct ContentView: View {
    @State private var library = MediaLibrary()
    @State private var registeredFolders = RegisteredFolders()
    @AppStorage("useSystemFilePicker") private var useSystemFilePicker = false
    @AppStorage("isDLNAEnabled") private var isDLNAEnabled = true
    private enum Presentation: Identifiable, Equatable {
        case folder, file, browser, player, dlna(RegisteredDLNAFolder?)
        var id: String {
            switch self {
            case .folder: "folder"
            case .file: "file"
            case .browser: "browser"
            case .player: "player"
            case .dlna: "dlna"
            }
        }
    }
    @State private var presentation: Presentation?
    @State private var pickedURL: URL?
    @State private var lastPlaybackURL: URL?
    @State private var pickedFile = false
    @State private var pickerHasDismissed = false
    @State private var showingLibrary = false
    @State private var showingPlayerFileBrowser = false
    @State private var playerFileError: String?
    @State private var pickerError: String?
    @State private var showingSavedFolders = false
    @State private var showSavedFoldersAfterDLNA = false
    @State private var folderAction: FolderAction?
    #if targetEnvironment(macCatalyst)
    @State private var macImporterPresented = false
    #endif
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            HomeView {
                showingSavedFolders = true
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
        .sheet(isPresented: $showingSavedFolders, onDismiss: handleFolderAction) {
            SavedFoldersView(folders: registeredFolders, isDLNAEnabled: $isDLNAEnabled,
                             onRemoveLocal: removeRegisteredLocal) { action in
                folderAction = action
                showingSavedFolders = false
            }
        }
        #if targetEnvironment(macCatalyst)
        .background {
            CatalystDocumentPicker(isPresented: $macImporterPresented,
                                   folder: true,
                                   directory: library.folderURL,
                                   completion: handleMacSelection)
                .frame(width: 0, height: 0)
        }
        #endif
        .alert("メディアを開けません", isPresented: Binding(get: { pickerError != nil }, set: { if !$0 { pickerError = nil } })) {
            Button("閉じる", role: .cancel) { pickerError = nil }
        } message: { Text(pickerError ?? "") }
        // One presenter serializes folder -> player -> folder transitions.
        .fullScreenCover(item: $presentation, onDismiss: presentationDidDismiss) { destination in
            presentedScreen(destination)
        }
        .task {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("--ui-fixtures") || arguments.contains("--ui-real-samples") {
                showingLibrary = true
                let folder = arguments.contains("--ui-real-samples") ? "RealSamples"
                    : arguments.contains("--ui-narrow-folder") ? "UIFixtures/SecondPlaylist" : "UIFixtures"
                let url = URL.documentsDirectory.appendingPathComponent(folder)
                await library.open(url, persist: false)
                try? registeredFolders.addLocal(url)
                return
            }
            #endif
            if library.hasSavedFolder {
                await library.restore(loadPlaylist: false)
                if library.error == nil, let url = library.folderURL {
                    try? registeredFolders.addLocal(url)
                }
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            #if targetEnvironment(macCatalyst)
            // Switching to another Mac app should not interrupt playback.
            library.playback.setActive(phase != .background)
            #else
            library.playback.setActive(phase == .active)
            #endif
        }
    }

    @ViewBuilder
    private func presentedScreen(_ destination: Presentation) -> some View {
        switch destination {
        case .folder:
            systemMediaPicker(isFolder: true)
        case .file:
            systemMediaPicker(isFolder: false)
        case .browser:
            if let root = library.folderURL {
                MediaFileBrowser(root: root, initialDirectory: library.currentDirectoryURL ?? root,
                                 initialFile: lastPlaybackURL) { url in
                    pickedFile = true
                    pickedURL = url
                    presentation = nil
                    finishFolderSelectionIfReady()
                } cancel: { presentation = nil }
            }
        case .dlna(let folder):
            DLNABrowser(registeredFolders: registeredFolders, initialFolder: folder) {
                showSavedFoldersAfterDLNA = true
                presentation = nil
            }
        case .player:
            localPlayerScreen()
        }
    }

    private func localPlayerScreen() -> some View {
        ZStack {
            PlayerScreen(playback: library.playback, folderName: library.folderName,
                         home: {
                             lastPlaybackURL = library.playback.state.currentURL
                             library.stop()
                             presentation = nil
                             showingLibrary = false
                         }, chooseFolder: {
                             lastPlaybackURL = library.playback.state.currentURL
                             library.playback.pause()
                             showingPlayerFileBrowser = true
                         }, browsingFiles: showingPlayerFileBrowser)
                .accessibilityHidden(showingPlayerFileBrowser)
            if showingPlayerFileBrowser, let root = library.folderURL {
                MediaFileBrowser(root: root, initialDirectory: library.currentDirectoryURL ?? root,
                                 initialFile: lastPlaybackURL) { url in
                    showingPlayerFileBrowser = false
                    Task {
                        await library.playFromSelection(url, autoplay: false)
                        playerFileError = library.error
                    }
                } cancel: {
                    showingPlayerFileBrowser = false
                }
                .accessibilityIdentifier("player.fileBrowserOverlay")
            }
        }
        .alert("メディアを開けません", isPresented: Binding(
            get: { playerFileError != nil },
            set: { if !$0 { playerFileError = nil } }
        )) {
            Button("閉じる", role: .cancel) { playerFileError = nil }
        } message: { Text(playerFileError ?? "") }
    }

    private func systemMediaPicker(isFolder: Bool) -> some View {
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
            Text(isFolder
                 ? "登録するフォルダーを開いて、右上の「開く」を押してください。"
                 : "再生を開始する動画・音声ファイルをタップしてください。")
                .accessibilityIdentifier(isFolder ? "picker.folderPrompt" : "picker.filePrompt")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
                .padding(.bottom, 8)
            SystemMediaPicker(folder: isFolder,
                              directory: isFolder ? library.folderURL : library.currentDirectoryURL) { url in
                pickedFile = !isFolder
                pickedURL = url
                presentation = nil
                finishFolderSelectionIfReady()
            }
            .id(isFolder)
        }
    }

    private func presentationDidDismiss() {
        showingPlayerFileBrowser = false
        playerFileError = nil
        // Escape/system dismissal bypasses the player's Home/Choose buttons.
        // Tear down its AVPlayer item and pending preparation on every exit.
        if let currentURL = library.playback.state.currentURL {
            lastPlaybackURL = currentURL
            library.stop()
            Logger(subsystem: "jp.nagu.ContinuousPlayer-for-iOS", category: "PlaybackLifecycle")
                .notice("Player dismissed: rate=\(library.playback.player.rate), hasItem=\(library.playback.player.currentItem != nil)")
        }
        if showSavedFoldersAfterDLNA {
            showSavedFoldersAfterDLNA = false
            showingSavedFolders = true
            return
        }
        pickerHasDismissed = true
        finishFolderSelectionIfReady()
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
                    do { try registeredFolders.addLocal(url) }
                    catch { pickerError = "フォルダーの登録に失敗しました。\(error.localizedDescription)"; return }
                    showingLibrary = false
                }
            }
        }
    }

    private func beginAuthorization() {
        lastPlaybackURL = nil
        #if targetEnvironment(macCatalyst)
        macImporterPresented = true
        #else
        pickerHasDismissed = false
        pickedURL = nil
        presentation = .folder
        #endif
    }

    private func handleFolderAction() {
        guard let action = folderAction else { return }
        folderAction = nil
        switch action {
        case .addLocal:
            beginAuthorization()
        case .addDLNA:
            presentation = .dlna(nil)
        case .dlna(let folder):
            presentation = .dlna(folder)
        case .local(let folder):
            Task {
                do {
                    let url = try registeredFolders.resolve(folder)
                    await library.open(url, loadPlaylist: false)
                    guard library.error == nil else { pickerError = library.error; return }
                    try? registeredFolders.addLocal(url)
                    pickerHasDismissed = false
                    pickedURL = nil
                    await beginSelection()
                } catch {
                    pickerError = "登録したフォルダーを開けません。再登録してください。\(error.localizedDescription)"
                }
            }
        }
    }

    private func removeRegisteredLocal(_ folder: RegisteredLocalFolder) {
        registeredFolders.removeLocal(folder)
        let removedURL = try? registeredFolders.resolve(folder)
        if (removedURL != nil && library.folderURL?.standardizedFileURL == removedURL?.standardizedFileURL)
            || (removedURL == nil && registeredFolders.local.isEmpty && library.hasSavedFolder) {
            library.forgetFolder()
        }
    }

    private func beginSelection() async {
        let canSelectFile = await library.prepareFileSelection()
        guard canSelectFile else {
            pickerError = library.error ?? "先に「OP / EDを選ぶ」で保存済みフォルダーを開くか、「フォルダーを追加」で登録してください。"
            return
        }
        pickerHasDismissed = false
        pickedURL = nil
        #if targetEnvironment(macCatalyst)
        presentation = .browser
        #else
        presentation = useSystemFilePicker ? .file : .browser
        #endif
    }

    #if targetEnvironment(macCatalyst)
    private func handleMacSelection(_ result: Result<URL, Error>) {
        Logger(subsystem: "jp.nagu.ContinuousPlayer-for-iOS", category: "FileSelection").notice("Mac folder importer completion")
        switch result {
        case .failure(let error):
            if (error as NSError).code != NSUserCancelledError {
                pickerError = error.localizedDescription
            }
        case .success(let url):
            Task {
                await library.authorizeFolder(url)
                guard library.error == nil else {
                    pickerError = library.error
                    return
                }
                do { try registeredFolders.addLocal(url) }
                catch { pickerError = "フォルダーの登録に失敗しました。\(error.localizedDescription)" }
            }
        }
    }
    #endif

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
                    Button(action: select) {
                        Label("OP / EDを選ぶ", systemImage: "folder.fill")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 18)
                            .background(LinearGradient(colors: [.teal, .indigo], startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 18))
                    }
                    .buttonStyle(.plain).frame(maxWidth: 320)
                    .accessibilityIdentifier("home.select")
                    #if targetEnvironment(macCatalyst)
                    Text("「OP / EDを選ぶ」から保存済みフォルダーの選択・追加ができます。")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    #else
                    Text("「OP / EDを選ぶ」からフォルダーの選択・追加ができます。\n登録したフォルダーは次回も使用できます。")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    #endif
                }
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .foregroundStyle(.white)
        .background(HomeAppearance.background.ignoresSafeArea())
    }
}

private struct SavedFoldersView: View {
    let folders: RegisteredFolders
    @Binding var isDLNAEnabled: Bool
    let onRemoveLocal: (RegisteredLocalFolder) -> Void
    let select: (FolderAction) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isCompactPhoneLandscape = false
    @State private var choosingSource = false
    @State private var pendingRemoval: Removal?

    private enum Removal: Identifiable {
        case local(RegisteredLocalFolder), dlna(RegisteredDLNAFolder)
        var id: String {
            switch self {
            case .local(let folder): "local-\(folder.id)"
            case .dlna(let folder): "dlna-\(folder.id)"
            }
        }
    }

    var body: some View {
        ZStack {
        NavigationStack {
            List {
                if !folders.local.isEmpty {
                    Section {
                        ForEach(folders.local.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { folder in
                            Button { select(.local(folder)) } label: {
                                folderRow(title: folder.name, icon: "folder.fill")
                            }
                            .buttonStyle(.plain)
                            .savedFolderRowStyle(compact: isCompactPhoneLandscape)
                            .accessibilityIdentifier("saved.local.\(folder.id)")
                            .contextMenu {
                                Button("登録解除", systemImage: "trash", role: .destructive) {
                                    pendingRemoval = .local(folder)
                                }
                            }
                            .swipeActions {
                                Button("登録解除", role: .destructive) { pendingRemoval = .local(folder) }
                            }
                        }
                    } header: { Text("端末のフォルダー").foregroundStyle(.cyan) }
                }
                if isDLNAEnabled && !folders.dlna.isEmpty {
                    Section {
                        ForEach(folders.dlna.sorted { $0.detail.localizedStandardCompare($1.detail) == .orderedAscending }) { folder in
                            Button { select(.dlna(folder)) } label: {
                                folderRow(title: folder.name, detail: folder.detail, icon: "network")
                            }
                            .buttonStyle(.plain)
                            .savedFolderRowStyle(compact: isCompactPhoneLandscape)
                            .accessibilityIdentifier("saved.dlna.\(folder.id)")
                            .contextMenu {
                                Button("登録解除", systemImage: "trash", role: .destructive) {
                                    pendingRemoval = .dlna(folder)
                                }
                            }
                            .swipeActions {
                                Button("登録解除", role: .destructive) { pendingRemoval = .dlna(folder) }
                            }
                        }
                    } header: { Text("DLNAフォルダー").foregroundStyle(.cyan) }
                }
                if folders.local.isEmpty && (!isDLNAEnabled || folders.dlna.isEmpty) {
                    ContentUnavailableView("登録したフォルダーはありません", systemImage: "folder.badge.plus",
                                           description: Text("「フォルダーを追加」から登録してください。"))
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, isCompactPhoneLandscape ? 40 : 44)
            .onGeometryChange(for: Bool.self) { geometry in
                UIDevice.current.userInterfaceIdiom == .phone && geometry.size.width > geometry.size.height
            } action: { _, isLandscape in
                isCompactPhoneLandscape = isLandscape
            }
            .scrollContentBackground(.hidden)
            .background(SavedFolderColors.background)
            .safeAreaInset(edge: .bottom, spacing: 12) {
                VStack(spacing: 8) {
                    Text("フォルダーを長押し、または左にスワイプすると登録を解除できます。ファイルは削除されません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button { choosingSource = true } label: {
                        Label("フォルダーを追加", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                    .frame(maxWidth: 430)
                    .accessibilityIdentifier("saved.addFolder")
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(SavedFolderColors.background)
                .overlay(alignment: .top) {
                    Rectangle().fill(SavedFolderColors.border).frame(height: 1)
                }
            }
            .navigationTitle("保存済みフォルダー")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .alert(item: $pendingRemoval) { removal in
                Alert(title: Text("登録を解除しますか？"),
                      message: Text("保存済み一覧から外します。フォルダーやファイルは削除されません。"),
                      primaryButton: .destructive(Text("登録解除")) {
                          switch removal {
                          case .local(let folder): onRemoveLocal(folder)
                          case .dlna(let folder): folders.removeDLNA(folder)
                          }
                      }, secondaryButton: .cancel())
            }
        }
        .savedFolderDialogStyle()
        .accessibilityHidden(choosingSource)
        if choosingSource {
            AddFolderSourceDialog(isDLNAEnabled: isDLNAEnabled, choose: { action in
                if case .addDLNA = action { isDLNAEnabled = true }
                choosingSource = false
                select(action)
            }, close: { choosingSource = false })
        }
        }
        .presentationBackground(Color.black.opacity(0.78))
    }

    private func folderRow(title: String, detail: String? = nil, icon: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .foregroundStyle(.cyan).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").foregroundStyle(.cyan)
        }
        .frame(maxWidth: .infinity, minHeight: isCompactPhoneLandscape ? 40 : 44)
        .contentShape(Rectangle())
    }
}

private enum SavedFolderColors {
    static let background = Color(red: 0.07, green: 0.10, blue: 0.20)
    static let row = Color(red: 0.10, green: 0.14, blue: 0.25)
    static let border = Color(red: 0.26, green: 0.32, blue: 0.44)
}

private extension View {
    func savedFolderRowStyle(compact: Bool) -> some View {
        self
            .listRowBackground(SavedFolderColors.row)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: compact ? 0 : 4, leading: 16, bottom: compact ? 0 : 4, trailing: 16))
    }

    func savedFolderDialogStyle() -> some View {
        self
            .frame(maxWidth: 880, maxHeight: 800)
            .background(SavedFolderColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(SavedFolderColors.border) }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.78))
            .preferredColorScheme(.dark)
            .tint(.cyan)
    }
}

private struct AddFolderSourceDialog: View {
    let isDLNAEnabled: Bool
    let choose: (FolderAction) -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.65).ignoresSafeArea()
                .onTapGesture { }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 16) {
                Text("保存済みフォルダー")
                    .font(.caption.weight(.semibold)).tracking(2).foregroundStyle(.cyan)
                Text("フォルダーを追加")
                    .font(.title2.bold()).foregroundStyle(.white)
                Text("追加するフォルダーの保存先を選んでください。")
                    .font(.subheadline).foregroundStyle(Color(white: 0.78))
                VStack(spacing: 8) {
                    sourceRow(title: "端末のフォルダー", detail: "端末・外部ストレージから選択",
                              icon: "folder.fill", identifier: "saved.source.local") {
                        choose(.addLocal)
                    }
                    sourceRow(title: "DLNAサーバー",
                              detail: isDLNAEnabled ? "NASのフォルダーを開いて登録" : "DLNA機能をオンにしてNASを開く",
                              icon: "network", identifier: "saved.source.dlna") {
                        choose(.addDLNA)
                    }
                }
                Button("閉じる", action: close)
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityIdentifier("saved.source.close")
            }
            .padding(22)
            .frame(maxWidth: 430)
            .background(SavedFolderColors.background, in: RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20).strokeBorder(SavedFolderColors.border)
            }
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
            .padding(16)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("saved.sourceDialog")
        }
    }

    private func sourceRow(title: String, detail: String, icon: String, identifier: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3).foregroundStyle(.cyan)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.white)
                    Text(detail).font(.caption).foregroundStyle(Color(white: 0.74))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                    .foregroundStyle(Color(white: 0.7))
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
                Text("オフの間は保存済みDLNAフォルダーを隠します。「フォルダーを追加」でDLNAサーバーを選ぶと再びオンになります。")
            }
            #if !targetEnvironment(macCatalyst)
            Section {
                Toggle("標準ファイルダイアログを使う", isOn: $useSystemFilePicker)
                    .accessibilityIdentifier("settings.useSystemFilePicker")
            } header: {
                Text("USBストレージのファイル選択")
            } footer: {
                Text("オフ：検索窓のないアプリ内一覧を使います。\nオン：標準ファイルダイアログを使います。")
            }
            #endif
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
        controller.title = folder ? "フォルダーを追加" : "開始ファイルを選ぶ"
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
