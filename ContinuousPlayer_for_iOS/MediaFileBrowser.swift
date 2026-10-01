import SwiftUI
import UIKit

/// Browses only inside the folder whose security scope MediaLibrary retains.
struct MediaFileBrowser: View {
    let root: URL
    let initialDirectory: URL
    let initialFile: URL?
    let select: (URL) -> Void
    let cancel: () -> Void
    @State private var path: [URL]
    @State private var lastSelections: [URL: String] = [:]

    init(root: URL, initialDirectory: URL, initialFile: URL?,
         select: @escaping (URL) -> Void, cancel: @escaping () -> Void) {
        self.root = root
        self.initialDirectory = initialDirectory
        self.initialFile = initialFile
        self.select = select
        self.cancel = cancel
        _path = State(initialValue: Self.folderPath(from: root, to: initialDirectory))
    }

    var body: some View {
        NavigationStack(path: $path) {
            folderView(root)
                .navigationDestination(for: URL.self) { directory in
                    folderView(directory)
                }
        }
        .fileBrowserDialogContainer()
    }

    private func folderView(_ directory: URL) -> some View {
        MediaFolderView(root: root, directory: directory,
                        lastSelectionPath: Binding(
                            get: { lastSelections[directory] ?? initialFile?.standardizedFileURL.path },
                            set: { lastSelections[directory] = $0 }
                        ), openFolder: { url in
            lastSelections[directory] = url.standardizedFileURL.path
            path.append(url)
        }, select: { url in
            lastSelections[directory] = url.standardizedFileURL.path
            select(url)
        }, cancel: cancel)
    }

    private static func folderPath(from root: URL, to directory: URL) -> [URL] {
        let rootComponents = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let directoryComponents = directory.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard directoryComponents.starts(with: rootComponents) else { return [] }
        var current = root
        return directoryComponents.dropFirst(rootComponents.count).map { component in
            current = current.appendingPathComponent(component, isDirectory: true)
            return current
        }
    }
}

private struct MediaFolderView: View {
    let root: URL
    let directory: URL
    @Binding var lastSelectionPath: String?
    let openFolder: (URL) -> Void
    let select: (URL) -> Void
    let cancel: () -> Void
    @State private var isCompactPhoneLandscape = false
    @State private var folders: [URL] = []
    @State private var files: [URL] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var error: String?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if isLoading {
                    ProgressView("ファイルを読み込み中…")
                } else if let error {
                    Text(error).foregroundStyle(.orange)
                } else {
                    if !folders.isEmpty {
                        Section {
                            ForEach(folders, id: \.self) { url in
                                Button {
                                    openFolder(url)
                                } label: {
                                    fileRow(url, isFolder: true)
                                }
                                .buttonStyle(.plain)
                                .fileBrowserEntryRowStyle()
                                .fileBrowserRowInsets(compact: isCompactPhoneLandscape)
                                .id(url.standardizedFileURL.path)
                            }
                        }
                    }
                    if !files.isEmpty {
                        Section {
                            ForEach(files, id: \.self) { url in
                                Button { select(url) } label: {
                                    fileRow(url, isFolder: false)
                                }
                                .buttonStyle(.plain)
                                .fileBrowserEntryRowStyle()
                                .fileBrowserRowInsets(compact: isCompactPhoneLandscape)
                                .id(url.standardizedFileURL.path)
                                .accessibilityLabel("\(url.lastPathComponent)を選択")
                            }
                        } footer: {
                            Text("選んだファイルから、このフォルダーの対象ファイルを最後まで再生します。")
                        }
                    } else {
                        Text("この階層には再生対象の動画・音声ファイルがありません。")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .fileBrowserListStyle()
            .fileBrowserRowHeight(isCompactPhoneLandscape)
            .onGeometryChange(for: Bool.self) { geometry in
                UIDevice.current.userInterfaceIdiom == .phone && geometry.size.width > geometry.size.height
            } action: { _, isLandscape in
                isCompactPhoneLandscape = isLandscape
            }
            .accessibilityIdentifier("picker.customList")
            .task(id: isLoading) {
                guard !isLoading, error == nil else { return }
                guard let path = lastSelectionPath,
                      (folders + files).contains(where: { $0.standardizedFileURL.path == path }) else { return }
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(path, anchor: .center)
            }
        }
        .navigationTitle(directory.lastPathComponent)
        .fileBrowserNavigationTitleStyle()
        .fileBrowserBackground()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("キャンセル", role: .cancel, action: cancel)
                    .accessibilityIdentifier("picker.cancel")
            }
        }
        .task {
            guard !hasLoaded else { return }
            await load()
        }
    }

    private func fileRow(_ url: URL, isFolder: Bool) -> some View {
        HStack(spacing: 16) {
            Image(systemName: isFolder ? "folder.fill" : "play.circle")
                .foregroundStyle(.cyan).frame(width: 28)
            Text(url.lastPathComponent)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if isFolder {
                Image(systemName: "chevron.right").foregroundStyle(.cyan)
            }
        }
        .frame(maxWidth: .infinity, minHeight: isCompactPhoneLandscape ? 40 : 44)
        .contentShape(Rectangle())
    }

    private func load() async {
        isLoading = true
        error = nil
        do {
            let entries = try await MediaScanner.browse(directory, within: root)
            guard !Task.isCancelled else { return }
            folders = entries.folders
            files = entries.files
            hasLoaded = true
        } catch {
            guard !Task.isCancelled else { return }
            self.error = "USBストレージの接続を確認してください。\(error.localizedDescription)"
        }
        isLoading = false
    }
}
