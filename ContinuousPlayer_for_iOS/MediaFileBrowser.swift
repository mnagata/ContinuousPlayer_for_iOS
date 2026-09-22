import SwiftUI

/// Browses only inside the folder whose security scope MediaLibrary retains.
struct MediaFileBrowser: View {
    let root: URL
    let initialDirectory: URL
    let initialFile: URL?
    let select: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var directory: URL?
    @State private var folders: [URL] = []
    @State private var files: [URL] = []
    @State private var isLoading = true
    @State private var error: String?
    @State private var returnFolderPath: String?

    private var current: URL { directory ?? initialDirectory }
    private var isRoot: Bool { current.standardizedFileURL.resolvingSymlinksInPath().path == root.standardizedFileURL.resolvingSymlinksInPath().path }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("ファイルを読み込み中…")
                } else if let error {
                    ContentUnavailableView {
                        Label("フォルダーを開けません", systemImage: "folder.badge.questionmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("再読み込み") { Task { await load() } }
                    }
                } else if folders.isEmpty && files.isEmpty {
                    ContentUnavailableView("対象ファイルがありません", systemImage: "music.note.list",
                                           description: Text("動画・音声ファイルのあるフォルダーを選んでください。"))
                } else {
                    ScrollViewReader { proxy in
                        List {
                            ForEach(folders, id: \.self) { url in
                                Button {
                                    returnFolderPath = nil
                                    directory = url
                                } label: {
                                    HStack {
                                        Image(systemName: "folder.fill")
                                        Text(url.lastPathComponent).foregroundStyle(.primary).lineLimit(2)
                                        Spacer(minLength: 8)
                                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                    }
                                    .frame(minHeight: 32).contentShape(Rectangle())
                                }
                                .id(url.standardizedFileURL.path)
                            }
                            ForEach(files, id: \.self) { url in
                                Button { select(url) } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "play.circle")
                                        Text(url.lastPathComponent)
                                            .foregroundStyle(.primary).lineLimit(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                    .frame(minHeight: 32).contentShape(Rectangle())
                                }
                                .id(url.standardizedFileURL.path)
                                .accessibilityLabel("\(url.lastPathComponent)を選択")
                            }
                        }
                        .listStyle(.plain)
                        .accessibilityIdentifier("picker.customList")
                        .onAppear {
                            // Restore the departed folder first, or the playback file on initial opening.
                            // Paths avoid mismatches from directory URLs with trailing slashes.
                            if let path = returnFolderPath,
                               folders.contains(where: { $0.standardizedFileURL.path == path }) {
                                proxy.scrollTo(path, anchor: .center)
                            } else if directory == nil, let path = initialFile?.standardizedFileURL.path,
                                      files.contains(where: { $0.standardizedFileURL.path == path }) {
                                proxy.scrollTo(path, anchor: .center)
                            }
                        }
                    }
                    .id(current)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(current.lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル", role: .cancel) { dismiss() }
                        .accessibilityIdentifier("picker.cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        returnFolderPath = current.standardizedFileURL.path
                        directory = current.deletingLastPathComponent()
                    } label: {
                        Label("上のフォルダー", systemImage: "arrow.up")
                    }
                    .disabled(isRoot || isLoading)
                    .accessibilityIdentifier("picker.parentFolder")
                }
            }
            .task(id: current) { await load() }
        }
    }

    private func load() async {
        let requested = current
        isLoading = true
        error = nil
        do {
            let entries = try await MediaScanner.browse(requested, within: root)
            guard !Task.isCancelled, requested == current else { return }
            folders = entries.folders
            files = entries.files
        } catch {
            guard !Task.isCancelled, requested == current else { return }
            self.error = "USBストレージの接続を確認してください。\(error.localizedDescription)"
        }
        isLoading = false
    }
}
