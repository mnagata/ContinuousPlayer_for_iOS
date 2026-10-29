import SwiftUI
import UIKit
#if !os(tvOS)
import UniformTypeIdentifiers
#endif

struct FileSelectionScreen: View {
    @Bindable var flow: FileSelectionCoordinator
    let home: () -> Void
    @State private var pendingRemoval: Removal?
    @State private var showsLocalPicker = false
    @FocusState private var focusID: String?
    @AccessibilityFocusState private var accessibilityFocusID: String?
    private enum Removal: Identifiable {
        case local(RegisteredLocalFolder), dlna(RegisteredDLNAFolder)
        var id: String {
            switch self {
            case .local(let folder): "saved.local.\(folder.id)"
            case .dlna(let folder): "saved.dlna.\(folder.id)"
            }
        }
    }
    private var cancelID: String {
        switch flow.page {
        case .saved: "saved.close"
        case .sources: "saved.source.close"
        case .folder(.local): "picker.cancel"
        default: "dlna.cancel"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                pageContent
                    .disabled(flow.busy)
                    .overlay {
                        if flow.showsLoading {
                            ProgressView("フォルダーを読み込み中…")
                                .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                                .accessibilityIdentifier("selection.loading")
                        }
                    }
                    .task(id: flow.focusRevision) {
                        guard !flow.busy else { return }
                        let id = flow.page == .saved ? (flow.selectedSavedID ?? flow.savedIDs.first ?? "saved.addFolder") : flow.selectedRowID
                        focusID = nil
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        if let id { proxy.scrollTo(id, anchor: .center) }
                        focusID = id; accessibilityFocusID = id
                    }
            }
            .navigationTitle(flow.title)
            .fileBrowserNavigationTitleStyle()
            .toolbar {
                if flow.page != .saved {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(flow.parentTitle, systemImage: "chevron.left") { flow.back() }
                            .accessibilityIdentifier("selection.back")
                    }
                }
                #if !os(tvOS)
                ToolbarItem(placement: .topBarTrailing) { cancelButton }
                #endif
                #if !os(tvOS)
                if flow.origin == .playback {
                    ToolbarItem(placement: .primaryAction) {
                        Button("ホームに戻る", systemImage: "house", action: home)
                            .accessibilityIdentifier("selection.home")
                    }
                }
                #endif
            }
            .safeAreaInset(edge: .bottom) { footer }
            .fileBrowserBackground()
        }
        .fileBrowserDialogContainer()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(flow.origin == .playback ? "player.fileBrowserOverlay" : "selection.flow")
        .fileBrowserBackShortcut(enabled: true) { flow.back() }
        #if os(tvOS)
        .onExitCommand { flow.back() }
        #endif
        .alert(item: $pendingRemoval) { removal in
            Alert(title: Text("登録を解除しますか？"), message: Text("ファイルは削除されません。"),
                  primaryButton: .destructive(Text("登録解除")) {
                      switch removal {
                      case .local(let folder): flow.removeLocal(folder)
                      case .dlna(let folder): flow.removeDLNA(folder)
                      }
                  }, secondaryButton: .cancel())
        }
        #if targetEnvironment(macCatalyst)
        .background {
            CatalystDocumentPicker(isPresented: $showsLocalPicker, folder: true, directory: nil) { result in
                guard !flow.isClosed else { return }
                if case .success(let url) = result { flow.registerLocal(url) }
                else if case .failure(let error) = result, (error as NSError).code != NSUserCancelledError {
                    flow.error = error.localizedDescription
                }
            }.frame(width: 0, height: 0)
        }
        #elseif !os(tvOS)
        .sheet(isPresented: $showsLocalPicker) {
            RegistrationFolderPicker { url in
                showsLocalPicker = false
                if let url, !flow.isClosed { flow.registerLocal(url) }
            }
        }
        #endif
    }

    @ViewBuilder private var pageContent: some View {
        switch flow.page {
        case .saved: savedList
        case .sources: sourceList
        case .servers:
            DLNAServersView(client: DLNAClient(), open: flow.openServer,
                            onConnectingChange: { flow.isConnecting = $0 })
                // Discovery permits manual input; the connection task owns its own disabled state.
                .disabled(false)
        case .folder:
            List {
                if let error = flow.error { Text(error).foregroundStyle(.orange) }
                ForEach(flow.rows) { row in
                    Button { flow.activate(row) } label: {
                        HStack(spacing: 16) {
                            Image(systemName: row.isFolder ? "folder.fill" : "play.circle").foregroundStyle(.cyan).frame(width: 28)
                            Text(displayName(row)).lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
                            if row.isFolder { Image(systemName: "chevron.right").foregroundStyle(.cyan) }
                        }.padding(.vertical, 8).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isRegistration && !row.isFolder)
                    .fileBrowserEntryRowStyle(isCurrent: flow.selectedRowID == row.id)
                    .focused($focusID, equals: row.id)
                    .accessibilityFocused($accessibilityFocusID, equals: row.id)
                    .accessibilityAddTraits(flow.selectedRowID == row.id ? .isSelected : [])
                    .id(row.id)
                    .accessibilityIdentifier(row.isFolder ? folderID(row) : "selection.file.\(row.id)")
                    .accessibilityLabel(row.isFolder ? row.name : fileLabel(row))
                }
                if flow.rows.isEmpty && !flow.isLoading && flow.error == nil {
                    Text("この階層には再生対象のファイルがありません。").foregroundStyle(.secondary)
                }
            }.fileBrowserListStyle().accessibilityIdentifier("picker.customList")
        }
    }
    private var savedList: some View {
        List {
            if let error = flow.error { Text(error).foregroundStyle(.orange) }
            #if !os(tvOS)
            if !flow.registrations.local.isEmpty {
                Section("端末のフォルダー") {
                    ForEach(flow.registrations.local.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { folder in
                        savedRow(id: "saved.local.\(folder.id)", name: folder.name, detail: nil, icon: "folder.fill",
                                 select: { flow.open(folder) }, remove: { if !flow.busy && !flow.isClosed { pendingRemoval = .local(folder) } })
                    }
                }
            }
            #endif
            if !flow.registrations.dlna.isEmpty {
                Section("DLNAフォルダー") {
                    ForEach(flow.registrations.dlna.sorted { $0.detail.localizedStandardCompare($1.detail) == .orderedAscending }) { folder in
                        savedRow(id: "saved.dlna.\(folder.id)", name: folder.name, detail: folder.detail, icon: "network",
                                 select: { flow.open(folder) }, remove: { if !flow.busy && !flow.isClosed { pendingRemoval = .dlna(folder) } })
                    }
                }
            }
            if flow.savedIDs.isEmpty {
                ContentUnavailableView("登録したフォルダーはありません", systemImage: "folder.badge.plus",
                                       description: Text("「フォルダーを追加」から登録してください。"))
            }
        }.fileBrowserListStyle()
    }
    private var sourceList: some View {
        List {
            Text("追加するフォルダーの保存先を選んでください。").foregroundStyle(.secondary)
            #if !os(tvOS)
            Button { showsLocalPicker = true } label: {
                Label("端末のフォルダー、端末・外部ストレージから選択", systemImage: "folder.fill")
            }.accessibilityIdentifier("saved.source.local")
            #endif
            Button(action: flow.showServers) {
                Label("DLNAサーバー、NASのフォルダーを開いて登録", systemImage: "network")
            }.accessibilityIdentifier("saved.source.dlna")
            if let error = flow.error { Text(error).foregroundStyle(.orange) }
        }.fileBrowserListStyle().accessibilityIdentifier("saved.sourceDialog")
    }
    private var isRegistration: Bool {
        if case .folder(let folder) = flow.page { return folder.isAdding }
        return false
    }
    @ViewBuilder private var footer: some View {
        VStack(spacing: 12) {
            if flow.page == .saved {
                Button(action: flow.showSources) { Label("フォルダーを追加", systemImage: "plus.circle.fill") }
                    .disabled(flow.busy).id("saved.addFolder")
                    .focused($focusID, equals: "saved.addFolder")
                    .accessibilityFocused($accessibilityFocusID, equals: "saved.addFolder")
                    .accessibilityIdentifier("saved.addFolder")
                Text("長押し・右クリックで登録を解除できます。ファイルは削除されません。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if case .folder = flow.page {
                HStack(spacing: 20) {
                    if isRegistration {
                        Button("このフォルダーを登録", systemImage: "bookmark", action: flow.registerCurrent)
                            .accessibilityIdentifier("dlna.registerFolder")
                    }
                    Button("再読み込み", systemImage: "arrow.clockwise", action: flow.reload)
                        .accessibilityIdentifier("selection.reload")
                }.disabled(flow.busy)
            }
            #if os(tvOS)
            HStack(spacing: 24) {
                cancelButton
                if flow.origin == .playback {
                    Button("ホームに戻る", systemImage: "house", action: home)
                        .accessibilityIdentifier("selection.home")
                }
            }
            #endif
        }
        .buttonStyle(.bordered)
        .padding(12).frame(maxWidth: .infinity)
        .background(FileBrowserColors.background)
    }
    private var cancelButton: some View {
        Button(flow.page == .saved && flow.origin == .home ? "閉じる" : "キャンセル", role: .cancel) { flow.cancelPage() }
            .fileBrowserCancelShortcut()
            .accessibilityIdentifier(cancelID)
    }
    private func savedRow(id: String, name: String, detail: String?, icon: String,
                          select: @escaping () -> Void, remove: @escaping () -> Void) -> some View {
        Button(action: select) {
            HStack(spacing: 16) {
                Image(systemName: icon).foregroundStyle(.cyan).frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(name).lineLimit(3)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right").foregroundStyle(.cyan)
            }.padding(.vertical, 10).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .highPriorityGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in remove() })
        .accessibilityAction(named: Text("登録解除"), remove)
        #if !os(tvOS)
        .swipeActions { Button("登録解除", role: .destructive, action: remove) }
        #endif
        .fileBrowserEntryRowStyle(isCurrent: flow.selectedSavedID == id)
        .focused($focusID, equals: id)
        .accessibilityFocused($accessibilityFocusID, equals: id)
        .accessibilityAddTraits(flow.selectedSavedID == id ? .isSelected : [])
        .id(id).accessibilityIdentifier(id)
        #if targetEnvironment(macCatalyst)
        .background { RegistrationSecondaryClick(action: remove).accessibilityHidden(true) }
        #elseif !os(tvOS)
        .overlay { RegistrationSecondaryClick(action: remove).accessibilityHidden(true) }
        #endif
    }
    private func folderID(_ row: SelectionRow) -> String { row.remote.map { "dlna.folder.\($0.id)" } ?? "selection.folder.\(row.id)" }
    private func fileLabel(_ row: SelectionRow) -> String { row.remote == nil ? "\(displayName(row))を選択" : "\(row.name)から連続再生" }
    private func displayName(_ row: SelectionRow) -> String {
        // DLNA display-name/badge unification is a later stage.
        row.remote == nil && !row.isFolder ? URL(fileURLWithPath: row.name).deletingPathExtension().lastPathComponent : row.name
    }
}

#if !os(tvOS)
#if targetEnvironment(macCatalyst)
@objc(CPRegistrationClickProtocol)
private protocol MacRegistrationClick: NSObjectProtocol {
    @objc(startSecondaryClickWithHandler:)
    func startSecondaryClick(withHandler handler: @escaping (Double, Double, Double, Double) -> Bool)
    func stopSecondaryClick()
}
#endif

/// Pointer handling is local to this row. Catalyst uses AppKit's local monitor
/// because UIKit does not deliver the secondary-click gesture for this List.
private struct RegistrationSecondaryClick: UIViewRepresentable {
    let action: () -> Void
    final class View: UIView {
        var action: (() -> Void)?
        #if targetEnvironment(macCatalyst)
        private var bridge: (any MacRegistrationClick)?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil, bridge == nil,
                  let url = Bundle.main.builtInPlugInsURL?.appendingPathComponent("MacPlaybackLifecycle.bundle"),
                  let type = Bundle(url: url)?.principalClass as? NSObject.Type,
                  let bridge = type.init() as? any MacRegistrationClick else { return }
            self.bridge = bridge
            bridge.startSecondaryClick { [weak self] x, y, width, height in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window, window.isKeyWindow,
                          width > 0, height > 0, !self.isHidden,
                          window.rootViewController?.presentedViewController == nil else { return false }
                    let point = CGPoint(x: x / width * window.bounds.width, y: y / height * window.bounds.height)
                    let local = self.convert(point, from: window)
                    guard self.bounds.contains(local) else { return false }
                    var ancestor: UIView? = self
                    while let view = ancestor {
                        if view.clipsToBounds && !view.bounds.contains(view.convert(point, from: window)) { return false }
                        ancestor = view.superview
                    }
                    DispatchQueue.main.async { [weak self] in self?.action?() }
                    return true
                }
            }
        }
        func stop() { bridge?.stopSecondaryClick(); bridge = nil }
        isolated deinit { bridge?.stopSecondaryClick() }
        #else
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            event?.buttonMask.contains(.secondary) == true
        }
        @objc func clicked() { action?() }
        func stop() {}
        #endif
    }
    func makeUIView(context: Context) -> View {
        let view = View()
        #if targetEnvironment(macCatalyst)
        view.isUserInteractionEnabled = false
        #else
        let click = UITapGestureRecognizer(target: view, action: #selector(View.clicked))
        click.buttonMaskRequired = .secondary
        view.addGestureRecognizer(click)
        #endif
        return view
    }
    func updateUIView(_ view: View, context: Context) {
        view.action = action
    }
    static func dismantleUIView(_ view: View, coordinator: Coordinator) { view.stop() }
    typealias Coordinator = Void
}

private struct RegistrationFolderPicker: UIViewControllerRepresentable {
    let completion: (URL?) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) { context.coordinator.completion = completion }
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var completion: (URL?) -> Void
        init(completion: @escaping (URL?) -> Void) { self.completion = completion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { completion(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { completion(nil) }
    }
}
#endif
