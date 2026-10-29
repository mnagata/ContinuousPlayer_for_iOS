import SwiftUI
import UIKit

struct DLNAServersView: View {
    let client: DLNAClient
    let open: (DLNAServer) -> Void
    var onConnectingChange: (Bool) -> Void = { _ in }
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
                    Button { open(server) } label: {
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
        .task(id: "\(isConnecting)-\(servers.count)") {
            guard !isConnecting, !editingAddress, let id = servers.first?.id else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            focusedServerID = id
        }
        .onChange(of: isConnecting) { _, value in onConnectingChange(value) }
        .onDisappear { onConnectingChange(false) }
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
