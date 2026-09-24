import SwiftUI

@main
struct ContinuousPlayerTVApp: App {
    var body: some Scene {
        WindowGroup { TVHomeScreen() }
    }
}

private struct TVHomeScreen: View {
    @State private var showsBrowser = false

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
            Button("DLNAサーバーから選ぶ") { showsBrowser = true }
                .accessibilityIdentifier("home.dlna")
                .padding(.top, 24)
            Text("Apple TVとNASを同じネットワークに接続してください。")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HomeAppearance.background.ignoresSafeArea())
        .tint(.cyan)
        .preferredColorScheme(.dark)
        .fullScreenCover(isPresented: $showsBrowser) {
            DLNABrowser()
                // The browser needs its own appearance: the home/player use dark backgrounds.
                .preferredColorScheme(.light)
                .tint(.blue)
                .presentationBackground(Color(white: 0.94))
        }
    }
}
