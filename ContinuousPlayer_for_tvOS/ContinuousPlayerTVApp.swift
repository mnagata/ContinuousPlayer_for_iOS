import SwiftUI

@main
struct ContinuousPlayerTVApp: App {
    var body: some Scene {
        WindowGroup { TVHomeScreen() }
    }
}

private struct TVHomeScreen: View {
    @State private var showsSavedFolders = false
    @State private var registeredFolders = RegisteredFolders()

    var body: some View {
        VStack(spacing: 36) {
            Image("PlayerMark")
                .resizable().scaledToFit().frame(width: 240, height: 240)
                .accessibilityHidden(true)
            Text("ContinuousPlayer")
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("ANIME OPENINGS / ENDINGS")
                .font(.headline).tracking(5).foregroundStyle(.cyan)
            Text("NASの動画を、OP / ED順に連続再生")
                .foregroundStyle(.white.opacity(0.8))
            Button("OP / EDを選ぶ") { showsSavedFolders = true }
                .accessibilityIdentifier("home.chooseFolder")
                .padding(.top, 24)
            Text("Apple TVとNASを同じネットワークに接続してください。")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HomeAppearance.background.ignoresSafeArea())
        .tint(.cyan)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showsSavedFolders) {
            TVSavedFoldersView(registeredFolders: registeredFolders)
                .preferredColorScheme(.dark)
                .tint(TVFolderColors.accent)
                .presentationBackground(Color.black.opacity(0.78))
        }
    }
}

private struct TVSavedFoldersView: View {
    let registeredFolders: RegisteredFolders
    @Environment(\.dismiss) private var dismiss
    @State private var browserSelection: BrowserSelection?
    @State private var pendingRemoval: RegisteredDLNAFolder?
    @FocusState private var focusedFolderID: String?
    @FocusState private var isAddFocused: Bool

    private struct BrowserSelection: Identifiable {
        let id = UUID()
        let folder: RegisteredDLNAFolder?
    }

    var body: some View {
        NavigationStack {
            List {
                if registeredFolders.dlna.isEmpty {
                    ContentUnavailableView("登録したフォルダーはありません", systemImage: "folder.badge.plus",
                                           description: Text("「フォルダーを追加」からNASのフォルダーを登録してください。"))
                } else {
                    Section {
                        ForEach(registeredFolders.dlna.sorted {
                            $0.detail.localizedStandardCompare($1.detail) == .orderedAscending
                        }) { folder in
                            Button {
                                browserSelection = BrowserSelection(folder: folder)
                            } label: {
                                HStack(spacing: 16) {
                                    Image(systemName: "network")
                                        .foregroundStyle(focusedFolderID == folder.id ? TVFolderColors.focusAccent : TVFolderColors.accent)
                                        .frame(width: 28)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(folder.name)
                                            .foregroundStyle(focusedFolderID == folder.id ? .black : .white)
                                            .lineLimit(3)
                                        Text(folder.detail)
                                            .font(.caption)
                                            .foregroundStyle(focusedFolderID == folder.id ? Color(white: 0.25) : Color(white: 0.75))
                                            .lineLimit(2)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(focusedFolderID == folder.id ? TVFolderColors.focusAccent : TVFolderColors.accent)
                                }
                                .frame(maxWidth: .infinity, minHeight: 56)
                                .padding(.horizontal, 22)
                                .padding(.vertical, 10)
                                .background(focusedFolderID == folder.id ? TVFolderColors.selection : TVFolderColors.row,
                                            in: RoundedRectangle(cornerRadius: 14))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.clear)
                            .focused($focusedFolderID, equals: folder.id)
                            .focusEffectDisabled()
                            .accessibilityIdentifier("saved.dlna.\(folder.id)")
                            .contextMenu {
                                Button("登録解除", systemImage: "trash", role: .destructive) {
                                    pendingRemoval = folder
                                }
                            }
                        }
                    } header: { Text("DLNAフォルダー").foregroundStyle(TVFolderColors.accent) }
                }
            }
            .listStyle(.plain)
            .background(TVFolderColors.background)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 12) {
                    Text("フォルダーを長押しすると登録を解除できます。ファイルは削除されません。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button {
                        browserSelection = BrowserSelection(folder: nil)
                    } label: {
                        TVFolderDialogAction(title: "フォルダーを追加", systemImage: "plus.circle.fill",
                                             isFocused: isAddFocused)
                    }
                    .buttonStyle(.plain)
                    .focused($isAddFocused)
                    .focusEffectDisabled()
                    .accessibilityIdentifier("saved.addFolder")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(TVFolderColors.background)
                .overlay(alignment: .top) {
                    Rectangle().fill(TVFolderColors.border).frame(height: 1)
                }
            }
            .navigationTitle("保存済みフォルダー")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                        .accessibilityIdentifier("saved.close")
                }
            }
            .alert("登録を解除しますか？", isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            )) {
                Button("登録解除", role: .destructive) {
                    if let pendingRemoval { registeredFolders.removeDLNA(pendingRemoval) }
                    pendingRemoval = nil
                }
                Button("キャンセル", role: .cancel) { pendingRemoval = nil }
            } message: {
                Text("保存済み一覧から外します。フォルダーやファイルは削除されません。")
            }
        }
        .frame(maxWidth: 1320, maxHeight: 900)
        .background(TVFolderColors.background)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay {
            RoundedRectangle(cornerRadius: 24).strokeBorder(TVFolderColors.border)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.78))
        .fullScreenCover(item: $browserSelection) { selection in
            DLNABrowser(registeredFolders: registeredFolders,
                        initialFolder: selection.folder,
                        onRegistered: { browserSelection = nil })
                .preferredColorScheme(.dark)
                .tint(TVFolderColors.accent)
                .presentationBackground(Color.black.opacity(0.78))
        }
    }
}

enum TVFolderColors {
    static let background = Color(red: 0.07, green: 0.10, blue: 0.20)
    static let row = Color(red: 0.10, green: 0.14, blue: 0.25)
    static let border = Color(red: 0.26, green: 0.32, blue: 0.44)
    static let accent = Color(red: 0.50, green: 0.78, blue: 0.82)
    static let selection = Color(red: 0.77, green: 0.87, blue: 0.89)
    static let action = Color(red: 0.65, green: 0.80, blue: 0.83)
    static let focusBorder = Color(red: 0.42, green: 0.62, blue: 0.66)
    static let removal = Color(red: 0.85, green: 0.76, blue: 0.67)
    static let focusAccent = Color(red: 0.02, green: 0.34, blue: 0.43)
}

struct TVFolderDialogAction: View {
    let title: String
    let systemImage: String
    let isFocused: Bool
    var fill: Color = TVFolderColors.action

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.black)
            .frame(width: 640, height: 76)
            .background(isFocused ? TVFolderColors.selection : fill,
                        in: RoundedRectangle(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(isFocused ? TVFolderColors.focusBorder : .clear, lineWidth: 4)
            }
    }
}
