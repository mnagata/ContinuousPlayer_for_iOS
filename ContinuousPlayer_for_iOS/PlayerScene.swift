import SwiftUI

struct PlayerScene<Home: View>: View {
    @State private var model = PlayerSceneModel()
    let homeContent: (@escaping () -> Void) -> Home

    var body: some View {
        ZStack {
            if !model.showsPlayer && model.selection == nil { homeLayer }
            else if !model.showsPlayer { Color.black.ignoresSafeArea() }
            if model.showsPlayer {
                player
                    .background(.black).ignoresSafeArea()
                    .accessibilityElement(children: .contain)
                    .accessibilityHidden(model.selection != nil || model.isPreparingSelection)
                    .allowsHitTesting(model.selection == nil && !model.isPreparingSelection)
                    .disabled(model.isPreparingSelection)
                if model.isPreparingSelection {
                    VStack(spacing: 20) {
                        ProgressView("ファイルを読み込み中…")
                        Button("ホームに戻る", systemImage: "house", action: model.home)
                            .accessibilityIdentifier("player.cancelPreparation")
                    }
                    .padding(28).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityIdentifier("player.selectionPreparation")
                }
            }
            if let selection = model.selection {
                FileSelectionScreen(flow: selection, home: model.home)
            }
        }
        .preferredColorScheme(.dark).tint(.cyan)
        .playbackSceneLifecycle(session: model.session, onEnd: model.home)
        #if os(tvOS)
        .onExitCommand(perform: exitAction)
        .onPlayPauseCommand {
            guard model.selection == nil, !model.playback.isPresenting, model.showsPlayer, !model.isPreparingSelection else { return }
            if model.playback.state.wantsToPlay { model.playback.pause() } else { model.playback.resume() }
        }
        #else
        .task { await model.startFixturesIfRequested() }
        #endif
    }
    @ViewBuilder private var homeLayer: some View {
        #if !os(tvOS)
        if model.showsFixturePlaylist {
            NavigationStack {
                PlaylistView(library: model.library, chooseFolder: model.openSelection, select: model.chooseFixture)
            }
        } else { homeContent(model.openSelection) }
        #else
        homeContent(model.openSelection)
        #endif
    }
    @ViewBuilder private var player: some View {
        #if os(tvOS)
        TVPlayerScreen(playback: model.playback, folderName: model.folderName,
                       home: model.home, chooseFolder: model.openSelection, browsingFiles: model.selection != nil)
        #else
        PlayerScreen(playback: model.playback, folderName: model.folderName,
                     home: model.home, chooseFolder: model.openSelection, browsingFiles: model.selection != nil)
        #endif
    }
    #if os(tvOS)
    private var exitAction: (() -> Void)? {
        // Selection and information own Back while they are on top.
        guard model.selection == nil, model.showsPlayer, !model.playback.isPresenting else { return nil }
        return model.isPreparingSelection ? model.home : model.openSelection
    }
    #endif
}
