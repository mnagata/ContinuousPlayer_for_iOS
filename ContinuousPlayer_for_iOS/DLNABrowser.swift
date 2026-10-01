import SwiftUI
import UIKit

struct DLNABrowser: View {
    let registeredFolders: RegisteredFolders
    let initialFolder: RegisteredDLNAFolder?
    let onRegistered: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var playback = PlaybackController()
    @State private var selection: Selection?
    @State private var playingFolderName = ""
    @State private var showingPlayerFileBrowser = false
    @State private var returnHome = false
    @State private var folderPath: [Folder] = []
    @State private var lastSelections: [Folder: String] = [:]
    @State private var reconnectError: String?
    @State private var isReconnecting = true
    @State private var showServerSelection = false
    private let client = DLNAClient()

    init(registeredFolders: RegisteredFolders, initialFolder: RegisteredDLNAFolder? = nil,
         onRegistered: @escaping () -> Void = {}) {
        self.registeredFolders = registeredFolders
        self.initialFolder = initialFolder
        self.onRegistered = onRegistered
    }

    private struct Selection: Identifiable {
        let id = UUID()
    }
    private struct Folder: Hashable {
        let server: DLNAServer
        let path: [RegisteredDLNAPath]

        var objectID: String { path.last?.id ?? "0" }
        var title: String { path.last?.title ?? server.name }
    }

    var body: some View {
        NavigationStack(path: $folderPath) {
            Group {
                if let initialFolder, !showServerSelection {
                    savedFolderRoot(initialFolder)
                } else {
                    DLNAServersView(client: client) { server in
                        Folder(server: server, path: [RegisteredDLNAPath(id: "0", title: server.name)])
                    }
                }
            }
            .navigationDestination(for: Folder.self) { folder in
                DLNAFolderView(client: client, server: folder.server, objectID: folder.objectID,
                               title: folder.title,
                               registeredFolders: registeredFolders,
                               registrationPath: folder.path,
                               canRegisterFolder: initialFolder == nil || showServerSelection,
                               onRegistered: onRegistered,
                               lastSelectionID: Binding(get: { lastSelections[folder] },
                                                        set: { lastSelections[folder] = $0 }),
                               openFolder: { entry in
                    lastSelections[folder] = entry.id
                    folderPath.append(Folder(server: folder.server,
                                             path: folder.path + [RegisteredDLNAPath(id: entry.id, title: entry.title)]))
                }) { entries, selected in
                    selectFile(entries, selected: selected, in: folder, presentPlayer: true)
                }
                .toolbar { cancelToolbar }
            }
            .toolbar { cancelToolbar }
        }
        .fileBrowserDialogContainer()
        .task(id: initialFolder?.id) { await openInitialFolder() }
        .fullScreenCover(item: $selection, onDismiss: {
            showingPlayerFileBrowser = false
            playback.setPlaylist([])
            if returnHome { dismiss() }
        }) { _ in
            #if os(tvOS)
            playerScreen(playback: playback, folderName: playingFolderName) {
                playback.pause()
                returnHome = true
                self.selection = nil
            } chooseFolder: {
                playback.pause()
                self.selection = nil
            }
            #else
            ZStack {
                PlayerScreen(playback: playback, folderName: playingFolderName,
                             home: {
                                 playback.pause()
                                 returnHome = true
                                 selection = nil
                             }, chooseFolder: {
                                 playback.pause()
                                 showingPlayerFileBrowser = true
                             }, browsingFiles: showingPlayerFileBrowser)
                    .accessibilityHidden(showingPlayerFileBrowser)
                if showingPlayerFileBrowser, let folder = folderPath.last {
                    PlaybackFileBrowser(client: client, initialFolder: folder,
                                        registeredFolders: registeredFolders,
                                        lastSelections: $lastSelections,
                                        cancel: { showingPlayerFileBrowser = false }) { entries, selected, folder in
                        selectFile(entries, selected: selected, in: folder, presentPlayer: false)
                    }
                    .accessibilityIdentifier("player.dlnaFileBrowserOverlay")
                }
            }
            #endif
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            #if targetEnvironment(macCatalyst)
            // Switching to another Mac app should not interrupt playback.
            playback.setActive(phase != .background)
            #else
            playback.setActive(phase == .active)
            #endif
        }
    }

    private func selectFile(_ entries: [DLNAEntry], selected: DLNAEntry,
                            in folder: Folder, presentPlayer: Bool) {
        var urls: [URL] = []
        var names: [URL: String] = [:]
        var sizes: [URL: Int64] = [:]
        // Different object IDs can refer to the same stream. Preserve its first slot.
        for entry in entries {
            guard let url = entry.resourceURL, names[url] == nil else { continue }
            urls.append(url)
            names[url] = entry.title
            sizes[url] = entry.size
        }
        guard let url = selected.resourceURL else { return }
        playback.setPlaylist(urls, displayNames: names, sizes: sizes)
        playback.select(url, autoplay: false)
        playingFolderName = "\(folder.server.name) / \(folder.title)"
        if presentPlayer { selection = Selection() }
        else {
            folderPath = folder.path.indices.map { index in
                Folder(server: folder.server, path: Array(folder.path[...index]))
            }
            showingPlayerFileBrowser = false
        }
    }

    #if !os(tvOS)
    private struct PlaybackFileBrowser: View {
        let client: DLNAClient
        let initialFolder: Folder
        let registeredFolders: RegisteredFolders
        @Binding var lastSelections: [Folder: String]
        let cancel: () -> Void
        let select: ([DLNAEntry], DLNAEntry, Folder) -> Void
        @State private var path: [Folder] = []

        var body: some View {
            NavigationStack(path: $path) {
                folderView(initialFolder)
                    .navigationDestination(for: Folder.self) { folder in
                        folderView(folder)
                    }
            }
            .fileBrowserDialogContainer()
        }

        private func folderView(_ folder: Folder) -> some View {
            DLNAFolderView(client: client, server: folder.server, objectID: folder.objectID,
                           title: folder.title, registeredFolders: registeredFolders,
                           registrationPath: folder.path, canRegisterFolder: false,
                           onRegistered: {},
                           lastSelectionID: Binding(get: { lastSelections[folder] },
                                                    set: { lastSelections[folder] = $0 }),
                           openFolder: { entry in
                lastSelections[folder] = entry.id
                path.append(Folder(server: folder.server,
                                   path: folder.path + [RegisteredDLNAPath(id: entry.id, title: entry.title)]))
            }) { entries, selected in
                select(entries, selected, folder)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル", role: .cancel, action: cancel)
                        .accessibilityIdentifier("dlna.cancel")
                }
            }
        }
    }
    #endif

    private func savedFolderRoot(_ folder: RegisteredDLNAFolder) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "network").font(.largeTitle).foregroundStyle(.cyan)
            Text(folder.name).font(.title3.bold()).multilineTextAlignment(.center)
            if isReconnecting {
                ProgressView("保存したDLNAフォルダーに接続中…")
            } else if let reconnectError {
                Text(reconnectError).foregroundStyle(.orange).multilineTextAlignment(.center)
                Button("再接続") { Task { await openInitialFolder() } }
            } else {
                Button("保存したフォルダーを開く") { Task { await openInitialFolder() } }
            }
            Button("DLNAサーバーを選ぶ") { showServerSelection = true }
                .disabled(isReconnecting)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("保存済みDLNAフォルダー")
        .fileBrowserNavigationTitleStyle()
        .fileBrowserBackground()
    }

    private func openInitialFolder() async {
        guard let initialFolder else { return }
        isReconnecting = true
        reconnectError = nil
        defer { isReconnecting = false }
        do {
            let server = try await reconnect(initialFolder)
            try Task.checkCancellation()
            guard !initialFolder.path.isEmpty else {
                throw DLNAError.message("保存されたフォルダーの階層情報がありません。")
            }
            folderPath = initialFolder.path.indices.map { index in
                Folder(server: server, path: Array(initialFolder.path[...index]))
            }
        } catch {
            reconnectError = "\(initialFolder.serverName)への接続を確認してください。\(error.localizedDescription)"
        }
    }

    private func reconnect(_ folder: RegisteredDLNAFolder) async throws -> DLNAServer {
        if let server = try? await client.server(at: folder.descriptionURL), server.id == folder.serverID {
            return server
        }
        if DLNADiscovery.isAvailable {
            for url in try await DLNADiscovery.locations() {
                try Task.checkCancellation()
                if let server = try? await client.server(at: url), server.id == folder.serverID {
                    return server
                }
            }
        }
        throw DLNAError.message("登録時のサーバーが見つかりません。")
    }

    @ViewBuilder
    private func playerScreen(playback: PlaybackController, folderName: String,
                              home: @escaping () -> Void, chooseFolder: @escaping () -> Void) -> some View {
        #if os(tvOS)
        TVPlayerScreen(playback: playback, folderName: folderName, home: home, chooseFolder: chooseFolder)
            .presentationBackground(.black)
        #else
        PlayerScreen(playback: playback, folderName: folderName, home: home, chooseFolder: chooseFolder)
        #endif
    }

    @ToolbarContentBuilder
    private var cancelToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            // Dismiss the entire picker, even when a nested folder is displayed.
            Button(role: .cancel) { dismiss() } label: {
                Text("キャンセル").dlnaToolbarLabelStyle()
            }
                .accessibilityIdentifier("dlna.cancel")
                .dlnaToolbarButtonStyle()
        }
    }
}

private struct DLNAServersView<Destination: Hashable>: View {
    let client: DLNAClient
    let destination: (DLNAServer) -> Destination
    @AppStorage("dlna.lastServerAddress") private var savedAddress = ""
    @State private var servers: [DLNAServer] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var refreshID = UUID()
    @State private var address = ""
    @State private var connection: Connection?
    @State private var isConnecting = false
    @State private var connectionError: DLNAConnectionIssue?
    @FocusState private var editingAddress: Bool
    @FocusState private var focusedServerID: String?
    #if os(tvOS)
    @FocusState private var isConnectFocused: Bool
    #endif
    private let canDiscover = DLNADiscovery.isAvailable

    private struct Connection: Equatable {
        let id = UUID()
        let address: String
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 7) {
                    Text("NAS / DLNA")
                        .font(.caption.weight(.semibold)).tracking(2).dlnaSectionHeadingStyle()
                    Text("DLNAサーバーを選ぶ")
                        .font(.title2.bold())
                    Text("サーバー \(servers.count)台 · 同じLANにあるNASを選んでください。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowBackground(Color.clear)
            }
            Section {
                ForEach(servers) { server in
                    NavigationLink(value: destination(server)) {
                        HStack(spacing: 16) {
                            Image(systemName: "network")
                                .font(.title2)
                                .foregroundStyle(serverRowAccent(for: server.id))
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(server.name).font(.headline)
                                    .foregroundStyle(serverRowText(for: server.id))
                                Text("DLNAサーバー · \(server.controlURL.host ?? server.descriptionURL.host ?? "NAS")")
                                    .font(.caption)
                                    .foregroundStyle(serverRowDetail(for: server.id))
                            }
                            Spacer(minLength: 0)
                        }
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .dlnaFocusedRowBackground(focused: focusedServerID == server.id)
                        .contentShape(Rectangle())
                    }
                    .dlnaTVPlainButtonStyle()
                    .focused($focusedServerID, equals: server.id)
                    .dlnaFocusEffectStyle()
                    .accessibilityLabel(server.name)
                }
                if canDiscover {
                    if isLoading { ProgressView("DLNAサーバーを検索中…") }
                    if !isLoading && servers.isEmpty {
                        Text("サーバーが見つからない場合は、下の欄にNASのIPアドレスを入力して接続してください。")
                            .foregroundStyle(.secondary)
                    }
                    if let error { Text(error).foregroundStyle(.orange) }
                    Button("再検索") { refreshID = UUID() }
                        .disabled(isLoading)
                        .accessibilityIdentifier("dlna.refreshServers")
                } else if servers.isEmpty {
                    Text("このアプリでは自動検索を利用できません。下の欄にNASのIPアドレスを入力して接続してください。")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("dlna.directConnectionNotice")
                }
            } header: { Text("サーバー").dlnaSectionHeadingStyle() }
            footer: {
                Text("初回はローカルネットワークへのアクセスを許可してください。拒否した場合は、設定アプリのContinuousPlayerで許可できます。")
                    .dlnaSupportingTextStyle()
            }
            .dlnaSettingsSectionStyle()
            Section {
                HStack {
                    TextField("NASのIPアドレス（例: 192.168.1.10）", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("dlna.serverAddress")
                        .focused($editingAddress)
                        .submitLabel(.go)
                        .onSubmit { connect() }
                        .dlnaAddressFieldStyle(isFocused: editingAddress)
                    if !address.isEmpty {
                        Button {
                            address = ""
                            connectionError = nil
                            editingAddress = true
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("入力したアドレスを消去")
                        .accessibilityIdentifier("dlna.clearAddress")
                    }
                }
                .disabled(isConnecting)
                #if os(tvOS)
                Button(action: connect) {
                    TVFolderDialogAction(title: "接続", systemImage: "link", isFocused: isConnectFocused)
                }
                .buttonStyle(.plain)
                .focused($isConnectFocused)
                .focusEffectDisabled()
                .frame(maxWidth: .infinity)
                .disabled(isConnecting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("dlna.connect")
                #else
                Button("接続", action: connect)
                    .disabled(isConnecting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("dlna.connect")
                #endif
                if let target = DLNAClient.descriptionURL(for: address) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("接続先: \(target.host ?? "") · ポート \(String(target.port ?? (target.scheme == "https" ? 443 : 80)))")
                            .font(.caption).foregroundStyle(.secondary)
                        if let hint = DLNAClient.managementPortHint(for: target) {
                            Text(hint).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                if isConnecting { ProgressView("NASに接続中…") }
                if let connectionError {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(connectionError.title, systemImage: "exclamationmark.triangle")
                            .font(.headline).foregroundStyle(.orange)
                            .accessibilityIdentifier("dlna.connectionErrorTitle")
                        Text(connectionError.guidance).font(.subheadline)
                            .accessibilityIdentifier("dlna.connectionErrorGuidance")
                        #if os(tvOS)
                        Text(connectionError.details).font(.caption)
                            .accessibilityIdentifier("dlna.connectionErrorDetails")
                        #else
                        DisclosureGroup("接続エラーの詳細") {
                            Text(connectionError.details).font(.caption).textSelection(.enabled)
                                .accessibilityIdentifier("dlna.connectionErrorDetails")
                        }
                        #endif
                    }
                }
                if !savedAddress.isEmpty {
                    Button("保存した接続先を削除", role: .destructive) {
                        savedAddress = ""
                        address = ""
                        connection = nil
                        servers = []
                        connectionError = nil
                    }
                    .disabled(isConnecting)
                }
            } header: { Text("Synology NASに接続").dlnaSectionHeadingStyle() }
            footer: {
                Text("SynologyではIPアドレスだけで接続できます（標準ポート50001）。ポートを指定する場合は「192.168.1.10:50001」の形式で入力してください。接続先は保存されます。ほかのDLNAサーバーはデバイス記述XMLのURLを入力できます。")
                    .dlnaSupportingTextStyle()
            }
            .dlnaSettingsSectionStyle()
            Section {
                Text("NASと同じネットワークに接続してください。Synologyでは、対象フォルダーのメディアインデックス登録と、メディアサーバーのDMAデバイスへのアクセス許可も確認してください。")
                    .font(.footnote)
            }
            .dlnaSettingsSectionStyle()
        }
        .dlnaServerListStyle()
        .navigationTitle("DLNAサーバー")
        .fileBrowserNavigationTitleStyle()
        .fileBrowserBackground()
        .task {
            guard connection == nil, !savedAddress.isEmpty else { return }
            address = savedAddress
            connect()
        }
        .task(id: refreshID) { if canDiscover { await discover() } }
        .task(id: connection) {
            guard let connection else { return }
            isConnecting = true
            defer { isConnecting = false }
            guard let url = DLNAClient.descriptionURL(for: connection.address) else {
                connectionError = DLNAConnectionIssue(title: "アドレスの書式を確認してください",
                    guidance: "例: 192.168.1.10 または 192.168.1.10:50001。ポート番号は半角数字の1〜65535で入力してください。完全なURLを使う場合は http:// または https:// で始めてください。",
                    details: "接続前の入力確認で停止しました。NASへの通信は行っていません。")
                return
            }
            do {
                let server = try await client.server(at: url)
                try Task.checkCancellation()
                add(server)
                savedAddress = connection.address
            } catch {
                if !Task.isCancelled {
                    connectionError = DLNAConnectionIssue.make(error: error, url: url)
                }
            }
        }
    }

    private func connect() {
        guard !isConnecting else { return }
        let value = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        editingAddress = false
        connectionError = nil
        connection = Connection(address: value)
    }

    private func serverRowText(for id: String) -> Color {
        #if os(tvOS)
        focusedServerID == id ? .black : .white
        #else
        .primary
        #endif
    }

    private func serverRowDetail(for id: String) -> Color {
        #if os(tvOS)
        focusedServerID == id ? Color(white: 0.25) : Color(white: 0.75)
        #else
        .secondary
        #endif
    }

    private func serverRowAccent(for id: String) -> Color {
        #if os(tvOS)
        focusedServerID == id ? TVFolderColors.focusAccent : TVFolderColors.accent
        #else
        .cyan
        #endif
    }

    private func add(_ server: DLNAServer) {
        servers.removeAll { $0.id == server.id }
        servers.append(server)
        servers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func discover() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            let locations = try await DLNADiscovery.locations()
            try Task.checkCancellation()
            // Resolve at most four descriptions at once, allowing slow/offline devices to time out.
            var failures = 0
            for start in stride(from: 0, to: locations.count, by: 4) {
                try Task.checkCancellation()
                let batch = Array(locations[start..<min(start + 4, locations.count)])
                await withTaskGroup(of: DLNAServer?.self) { group in
                    for url in batch {
                        group.addTask { try? await client.server(at: url) }
                    }
                    for await server in group {
                        guard !Task.isCancelled else { group.cancelAll(); break }
                        if let server { add(server) } else { failures += 1 }
                    }
                }
            }
            if failures > 0 && !Task.isCancelled {
                error = "\(failures)件のサーバーから詳細を取得できませんでした。NASのアクセス許可と接続を確認してください。"
            }
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}

private struct DLNAFolderView: View {
    let client: DLNAClient
    let server: DLNAServer
    let objectID: String
    let title: String
    let registeredFolders: RegisteredFolders
    let registrationPath: [RegisteredDLNAPath]
    let canRegisterFolder: Bool
    let onRegistered: () -> Void
    @Binding var lastSelectionID: String?
    let openFolder: (DLNAEntry) -> Void
    let play: ([DLNAEntry], DLNAEntry) -> Void
    @State private var isCompactPhoneLandscape = false
    @State private var entries: [DLNAEntry] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var refreshID = UUID()
    @State private var loadedRefreshID: UUID?
    @FocusState private var focusedEntryID: String?
    #if os(tvOS)
    @FocusState private var isRegisterFocused: Bool
    #endif
    private var folders: [DLNAEntry] { entries.filter(\.isContainer) }
    private var playable: [DLNAEntry] { entries.filter { !$0.isContainer && $0.resourceURL != nil } }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if isLoading {
                    ProgressView("フォルダーを読み込み中…")
                } else if let error {
                    Text(error).foregroundStyle(.orange)
                } else {
                    if !folders.isEmpty {
                        Section {
                            ForEach(folders) { entry in
                                Button { openFolder(entry) } label: {
                                    HStack(spacing: 16) {
                                        Image(systemName: "folder.fill")
                                            .foregroundStyle(entryAccent(for: entry.id)).frame(width: 28)
                                        Text(entry.title)
                                            .foregroundStyle(entryText(for: entry.id))
                                            .lineLimit(3)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(entryAccent(for: entry.id))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: isCompactPhoneLandscape ? 40 : 44)
                                    .dlnaFocusedRowBackground(focused: focusedEntryID == entry.id)
                                    .contentShape(Rectangle())
                                }
                                .dlnaFolderButtonStyle()
                                .fileBrowserEntryRowStyle()
                                .fileBrowserRowInsets(compact: isCompactPhoneLandscape)
                                .id(entry.id)
                                .focused($focusedEntryID, equals: entry.id)
                                .dlnaFocusEffectStyle()
                                .accessibilityIdentifier("dlna.folder.\(entry.id)")
                            }
                        }
                    }
                    if !playable.isEmpty {
                        Section {
                            ForEach(playable) { entry in
                                Button {
                                    lastSelectionID = entry.id
                                    play(playable, entry)
                                } label: {
                                    HStack(spacing: 16) {
                                        Image(systemName: "play.circle")
                                            .foregroundStyle(entryAccent(for: entry.id)).frame(width: 28)
                                        Text(entry.title)
                                            .foregroundStyle(entryText(for: entry.id))
                                            .lineLimit(3)
                                            .fixedSize(horizontal: false, vertical: true)
                                        Spacer(minLength: 0)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: isCompactPhoneLandscape ? 40 : 44)
                                    .dlnaFocusedRowBackground(focused: focusedEntryID == entry.id)
                                    .contentShape(Rectangle())
                                }
                                .dlnaFolderButtonStyle()
                                .fileBrowserEntryRowStyle()
                                .fileBrowserRowInsets(compact: isCompactPhoneLandscape)
                                .id(entry.id)
                                .focused($focusedEntryID, equals: entry.id)
                                .dlnaFocusEffectStyle()
                                .accessibilityLabel("\(entry.title)から連続再生")
                            }
                        } footer: { Text("選んだファイルから、このフォルダーのMP4／M4Vを最後まで再生します。") }
                    } else {
                        Text("この階層には再生対象のMP4／M4Vがありません。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fileBrowserListStyle()
            .fileBrowserRowHeight(isCompactPhoneLandscape)
            #if !os(tvOS)
            .onGeometryChange(for: Bool.self) { geometry in
                UIDevice.current.userInterfaceIdiom == .phone && geometry.size.width > geometry.size.height
            } action: { _, isLandscape in
                isCompactPhoneLandscape = isLandscape
            }
            #endif
            .task(id: isLoading) {
                // NavigationStack may recreate the parent; restore by the server's stable object ID.
                guard !isLoading, error == nil, let id = lastSelectionID,
                      entries.contains(where: { $0.id == id }) else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(id, anchor: .center)
                await Task.yield()
                guard !Task.isCancelled else { return }
                focusedEntryID = id
            }
        }
        .navigationTitle(title).fileBrowserNavigationTitleStyle()
        .fileBrowserBackground()
        .toolbar {
            #if os(tvOS)
            ToolbarItem(placement: .primaryAction) {
                Button("再読み込み", systemImage: "arrow.clockwise") { refreshID = UUID() }
                    .disabled(isLoading)
            }
            #else
            if !canRegisterFolder {
                ToolbarItem(placement: .primaryAction) {
                    Button("再読み込み", systemImage: "arrow.clockwise") { refreshID = UUID() }
                        .disabled(isLoading)
                }
            }
            #endif
        }
        .safeAreaInset(edge: .bottom) {
            if canRegisterFolder {
                #if os(tvOS)
                VStack(spacing: 10) {
                    Text(isRegistered ? "このフォルダーは保存済みです。" : "現在開いているフォルダーを保存済み一覧に追加します。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(action: toggleRegistration) {
                        TVFolderDialogAction(title: isRegistered ? "登録解除" : "このフォルダーを登録",
                                             systemImage: isRegistered ? "bookmark.slash" : "bookmark.fill",
                                             isFocused: isRegisterFocused,
                                             fill: isRegistered ? TVFolderColors.removal : TVFolderColors.action)
                    }
                    .buttonStyle(.plain)
                    .focused($isRegisterFocused)
                    .focusEffectDisabled()
                    .accessibilityIdentifier("dlna.registerFolder")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(Color(red: 0.07, green: 0.10, blue: 0.20))
                .overlay(alignment: .top) {
                    Rectangle().fill(Color(red: 0.26, green: 0.32, blue: 0.44)).frame(height: 1)
                }
                #else
                HStack(spacing: 12) {
                    Button(action: toggleRegistration) {
                        Label(isRegistered ? "登録解除" : "このフォルダーを登録",
                              systemImage: isRegistered ? "bookmark.slash" : "bookmark")
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                    .accessibilityIdentifier("dlna.registerFolder")
                    Button("再読み込み", systemImage: "arrow.clockwise") { refreshID = UUID() }
                        .frame(minHeight: 48)
                        .disabled(isLoading)
                }
                .buttonStyle(.bordered)
                .tint(.cyan)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(red: 0.07, green: 0.10, blue: 0.20))
                #endif
            }
        }
        .task(id: refreshID) {
            // Keep the populated list when popping back; explicit reload still fetches fresh data.
            guard loadedRefreshID != refreshID else { return }
            isLoading = true
            error = nil
            defer { isLoading = false }
            do {
                let result = try await client.browse(server, objectID: objectID)
                try Task.checkCancellation()
                let folders = MediaScanner.sortFolders(result.filter(\.isContainer), name: { $0.title })
                let files = PlaylistSorter.sort(result.filter { !$0.isContainer }, name: { $0.title }, namesAreTitles: true)
                entries = folders + files
                loadedRefreshID = refreshID
            } catch {
                if !Task.isCancelled { self.error = error.localizedDescription }
            }
        }
    }

    private var isRegistered: Bool {
        registeredFolders.contains(server, objectID: objectID)
    }

    private func entryText(for id: String) -> Color {
        #if os(tvOS)
        focusedEntryID == id ? .black : .white
        #else
        .primary
        #endif
    }

    private func entryAccent(for id: String) -> Color {
        #if os(tvOS)
        focusedEntryID == id ? TVFolderColors.focusAccent : TVFolderColors.accent
        #else
        .cyan
        #endif
    }

    private func toggleRegistration() {
        let wasRegistered = isRegistered
        registeredFolders.toggleDLNA(server: server, path: registrationPath)
        if !wasRegistered { onRegistered() }
    }
}

#Preview("DLNAサーバー") { DLNABrowser(registeredFolders: RegisteredFolders()) }

private extension View {



    func dlnaFolderButtonStyle() -> some View {
        self.buttonStyle(.plain)
    }

    @ViewBuilder
    func dlnaTVPlainButtonStyle() -> some View {
        #if os(tvOS)
        self.buttonStyle(.plain)
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaFocusedRowBackground(focused: Bool) -> some View {
        #if os(tvOS)
        self
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(focused ? TVFolderColors.selection : TVFolderColors.row,
                        in: RoundedRectangle(cornerRadius: 14))
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaFocusEffectStyle() -> some View {
        #if os(tvOS)
        self.focusEffectDisabled()
        #else
        self
        #endif
    }





    @ViewBuilder
    func dlnaSettingsSectionStyle() -> some View {
        #if os(tvOS)
        self.listRowBackground(Color(red: 0.10, green: 0.14, blue: 0.25))
        #else
        self
            .listRowBackground(Color(red: 0.10, green: 0.14, blue: 0.25))
            .listRowSeparator(.hidden)
        #endif
    }

    @ViewBuilder
    func dlnaToolbarButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.borderedProminent).tint(TVFolderColors.accent)
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaSupportingTextStyle() -> some View {
        self.font(.footnote).foregroundStyle(Color(white: 0.75))
    }

    @ViewBuilder
    func dlnaServerListStyle() -> some View {
        #if os(tvOS)
        self.listStyle(.plain)
            .background(Color(red: 0.07, green: 0.10, blue: 0.20))
        #else
        self.listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Color(red: 0.07, green: 0.10, blue: 0.20))
        #endif
    }

    @ViewBuilder
    func dlnaToolbarLabelStyle() -> some View {
        #if os(tvOS)
        self.foregroundStyle(.black)
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaSectionHeadingStyle() -> some View {
        #if os(tvOS)
        self.foregroundStyle(TVFolderColors.accent)
        #else
        self.foregroundStyle(.cyan)
        #endif
    }


    @ViewBuilder
    func dlnaAddressFieldStyle(isFocused: Bool) -> some View {
        #if os(tvOS)
        self.padding(12)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isFocused ? TVFolderColors.focusBorder : Color.white.opacity(0.2),
                                  lineWidth: isFocused ? 3 : 2)
            }
        #else
        self.padding(10)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isFocused ? Color.cyan : Color.white.opacity(0.2), lineWidth: isFocused ? 2 : 1)
            }
        #endif
    }

}
