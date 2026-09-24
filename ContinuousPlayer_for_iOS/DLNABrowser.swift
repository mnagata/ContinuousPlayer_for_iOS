import SwiftUI

struct DLNABrowser: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var playback = PlaybackController()
    @State private var selection: Selection?
    @State private var returnHome = false
    @State private var folderPath: [Folder] = []
    @State private var lastSelections: [Folder: String] = [:]
    private let client = DLNAClient()

    private struct Selection: Identifiable {
        let id = UUID()
        let folderName: String
    }
    private struct Folder: Hashable {
        let server: DLNAServer
        let objectID: String
        let title: String
    }

    var body: some View {
        NavigationStack(path: $folderPath) {
            DLNAServersView(client: client) { server in
                Folder(server: server, objectID: "0", title: server.name)
            }
            .navigationDestination(for: Folder.self) { folder in
                DLNAFolderView(client: client, server: folder.server, objectID: folder.objectID,
                               title: folder.title,
                               lastSelectionID: Binding(get: { lastSelections[folder] },
                                                        set: { lastSelections[folder] = $0 }),
                               openFolder: { entry in
                    lastSelections[folder] = entry.id
                    folderPath.append(Folder(server: folder.server, objectID: entry.id, title: entry.title))
                }) { entries, selected in
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
                    selection = Selection(folderName: "\(folder.server.name) / \(folder.title)")
                }
                .toolbar { cancelToolbar }
            }
            .toolbar { cancelToolbar }
        }
        .fullScreenCover(item: $selection, onDismiss: {
            playback.setPlaylist([])
            if returnHome { dismiss() }
        }) { selection in
            playerScreen(playback: playback, folderName: selection.folderName) {
                playback.pause()
                returnHome = true
                self.selection = nil
            } chooseFolder: {
                playback.pause()
                self.selection = nil
            }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in playback.setActive(phase == .active) }
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
    private let canDiscover = DLNADiscovery.isAvailable

    private struct Connection: Equatable {
        let id = UUID()
        let address: String
    }

    var body: some View {
        List {
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
                Button("接続", action: connect)
                    .disabled(isConnecting || address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("dlna.connect")
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
                ForEach(servers) { server in
                    NavigationLink(value: destination(server)) {
                        Label(server.name, systemImage: "externaldrive.connected.to.line.below")
                    }
                }
                if canDiscover {
                    if isLoading { ProgressView("DLNAサーバーを検索中…") }
                    if !isLoading && servers.isEmpty {
                        Text("サーバーが見つからない場合は、上の欄にNASのIPアドレスを入力して接続してください。")
                            .foregroundStyle(.secondary)
                    }
                    if let error { Text(error).foregroundStyle(.orange) }
                    Button("再検索") { refreshID = UUID() }
                        .disabled(isLoading)
                        .accessibilityIdentifier("dlna.refreshServers")
                } else if servers.isEmpty {
                    Text("このアプリでは自動検索を利用できません。上の欄にNASのIPアドレスを入力して接続してください。")
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
                Text("NASと同じネットワークに接続してください。Synologyでは、対象フォルダーのメディアインデックス登録と、メディアサーバーのDMAデバイスへのアクセス許可も確認してください。")
                    .font(.footnote)
            }
            .dlnaSettingsSectionStyle()
        }
        .dlnaServerListStyle()
        .navigationTitle("DLNAサーバー")
        .dlnaNavigationTitleStyle()
        .dlnaBrowserBackground()
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
    @Binding var lastSelectionID: String?
    let openFolder: (DLNAEntry) -> Void
    let play: ([DLNAEntry], DLNAEntry) -> Void
    @State private var entries: [DLNAEntry] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var refreshID = UUID()
    @State private var loadedRefreshID: UUID?
    @FocusState private var focusedEntryID: String?
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
                        Section("フォルダー") {
                            ForEach(folders) { entry in
                                Button { openFolder(entry) } label: {
                                    Label(entry.title, systemImage: "folder")
                                }
                                .id(entry.id)
                                .focused($focusedEntryID, equals: entry.id)
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
                                    Label(entry.title, systemImage: "play.circle")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .id(entry.id)
                                .focused($focusedEntryID, equals: entry.id)
                                .accessibilityLabel("\(entry.title)から連続再生")
                            }
                        } header: { Text("\(playable.count)件 · OP / ED順") }
                        footer: { Text("選んだファイルから、このフォルダーのMP4／M4Vを最後まで再生します。") }
                    } else {
                        Text("この階層には再生対象のMP4／M4Vがありません。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
        .navigationTitle(title).dlnaNavigationTitleStyle()
        .dlnaBrowserBackground()
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("再読み込み", systemImage: "arrow.clockwise") { refreshID = UUID() }
                    .disabled(isLoading)
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
}

#Preview("DLNAサーバー") { DLNABrowser() }

private extension View {
    @ViewBuilder
    func dlnaSettingsSectionStyle() -> some View {
        #if os(tvOS)
        listRowBackground(Color.white)
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaToolbarButtonStyle() -> some View {
        #if os(tvOS)
        buttonStyle(.borderedProminent).tint(.blue)
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaSupportingTextStyle() -> some View {
        #if os(tvOS)
        font(.footnote)
            .foregroundStyle(Color(white: 0.35))
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaServerListStyle() -> some View {
        #if os(tvOS)
        listStyle(.grouped)
            .frame(maxWidth: 1320)
            .frame(maxWidth: .infinity)
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaToolbarLabelStyle() -> some View {
        #if os(tvOS)
        foregroundStyle(.black)
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaSectionHeadingStyle() -> some View {
        #if os(tvOS)
        foregroundStyle(Color(white: 0.25))
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaBrowserBackground() -> some View {
        #if os(tvOS)
        background(Color(white: 0.94))
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaAddressFieldStyle(isFocused: Bool) -> some View {
        #if os(tvOS)
        padding(12)
            .background(.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isFocused ? Color.blue : Color(white: 0.5), lineWidth: isFocused ? 4 : 2)
            }
        #else
        self
        #endif
    }

    @ViewBuilder
    func dlnaNavigationTitleStyle() -> some View {
        #if os(tvOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
