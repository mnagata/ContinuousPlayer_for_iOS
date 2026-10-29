import SwiftUI

@main
struct ContinuousPlayerTVApp: App {
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--common-spec-probe") { CommonSpecProbeScreen() }
            else { TVHomeScreen() }
            #else
            TVHomeScreen()
            #endif
        }
    }
}

private struct TVHomeScreen: View {
    var body: some View {
        PlayerScene { select in TVHomeContent(select: select) }
    }
}

private struct TVHomeContent: View {
    let select: () -> Void
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
            Button("OP / EDを選ぶ", action: select)
                .accessibilityIdentifier("home.chooseFolder")
                .padding(.top, 24)
            Text("Apple TVとNASを同じネットワークに接続してください。")
                .font(.caption).foregroundStyle(.white.opacity(0.8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HomeAppearance.background.ignoresSafeArea())
        .tint(.cyan)
        .preferredColorScheme(.dark)
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
