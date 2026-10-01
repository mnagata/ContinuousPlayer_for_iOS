import SwiftUI
import UIKit

/// Browses only inside the folder whose security scope MediaLibrary retains.
struct MediaFileBrowser: View {
    let root: URL
    let initialDirectory: URL
    let initialFile: URL?
    let select: (URL) -> Void
    let cancel: () -> Void
    @State private var isCompactPhoneLandscape = false
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
                            if !folders.isEmpty {
                                Section("フォルダー") {
                                    ForEach(folders, id: \.self) { url in
                                        Button {
                                            returnFolderPath = nil
                                            directory = url
                                        } label: {
                                            HStack(spacing: 16) {
                                                Image(systemName: "folder.fill")
                                                    .foregroundStyle(.cyan).frame(width: 28)
                                                Text(url.lastPathComponent)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(3)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Spacer(minLength: 0)
                                                Image(systemName: "chevron.right").foregroundStyle(.cyan)
                                            }
                                            .frame(maxWidth: .infinity, minHeight: isCompactPhoneLandscape ? 40 : 44)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .mediaBrowserRowStyle(compact: isCompactPhoneLandscape)
                                        .id(url.standardizedFileURL.path)
                                    }
                                }
                            }
                            if !files.isEmpty {
                                Section {
                                    ForEach(files, id: \.self) { url in
                                        Button { select(url) } label: {
                                            HStack(spacing: 16) {
                                                Image(systemName: "play.circle")
                                                    .foregroundStyle(.cyan).frame(width: 28)
                                                Text(url.lastPathComponent)
                                                    .foregroundStyle(.primary)
                                                    .lineLimit(3)
                                                    .fixedSize(horizontal: false, vertical: true)
                                                Spacer(minLength: 0)
                                            }
                                            .frame(maxWidth: .infinity, minHeight: isCompactPhoneLandscape ? 40 : 44)
                                            .contentShape(Rectangle())
                                        }
                                        .buttonStyle(.plain)
                                        .mediaBrowserRowStyle(compact: isCompactPhoneLandscape)
                                        .id(url.standardizedFileURL.path)
                                        .accessibilityLabel("\(url.lastPathComponent)を選択")
                                    }
                                } header: {
                                    Text("\(files.count)件 · OP / ED順").foregroundStyle(.cyan)
                                } footer: {
                                    Text("選んだファイルから、このフォルダーの対象ファイルを最後まで再生します。")
                                }
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
                        .background(MediaBrowserColors.background)
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
            .background(MediaBrowserColors.background)
            .navigationTitle(current.lastPathComponent)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("キャンセル", role: .cancel, action: cancel)
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
        .mediaBrowserDialogStyle()
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

private enum MediaBrowserColors {
    static let background = Color(red: 0.07, green: 0.10, blue: 0.20)
    static let row = Color(red: 0.10, green: 0.14, blue: 0.25)
}

private extension View {
    func mediaBrowserRowStyle(compact: Bool) -> some View {
        self
            .listRowBackground(MediaBrowserColors.row)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: compact ? 0 : 4, leading: 16, bottom: compact ? 0 : 4, trailing: 16))
    }

    func mediaBrowserDialogStyle() -> some View {
        self
            .frame(maxWidth: 880, maxHeight: 800)
            .background(MediaBrowserColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Color(red: 0.26, green: 0.32, blue: 0.44)) }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.78))
            .preferredColorScheme(.dark)
            .tint(.cyan)
    }
}
