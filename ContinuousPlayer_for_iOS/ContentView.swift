import SwiftUI

struct ContentView: View {
    var body: some View {
        PlayerScene { select in HomeView(select: select) }
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

struct PlaylistView: View {
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
                } footer: { Text("選んだファイルから順に、最後まで連続再生します。") }
            }
        }
        .navigationTitle("OP / EDを選ぶ")
        .navigationBarTitleDisplayMode(.inline)
    }
}


#Preview("ホーム") { ContentView() }
