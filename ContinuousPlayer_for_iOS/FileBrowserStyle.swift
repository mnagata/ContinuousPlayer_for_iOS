import SwiftUI

/// Keeps local and DLNA folder/file dialogs visually consistent.
extension View {
    @ViewBuilder
    func fileBrowserRowHeight(_ compact: Bool) -> some View {
        #if os(tvOS)
        self
        #else
        self.environment(\.defaultMinListRowHeight, compact ? 40 : 44)
        #endif
    }

    @ViewBuilder
    func fileBrowserRowInsets(compact: Bool) -> some View {
        #if os(tvOS)
        self
        #else
        self.listRowInsets(EdgeInsets(top: compact ? 0 : 4, leading: 16, bottom: compact ? 0 : 4, trailing: 16))
        #endif
    }

    @ViewBuilder
    func fileBrowserDialogContainer() -> some View {
        #if os(tvOS)
        self
            .frame(maxWidth: 1320, maxHeight: 900)
            .background(FileBrowserColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .overlay {
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(FileBrowserColors.border)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.78))
            .preferredColorScheme(.dark)
        #else
        self
            .frame(maxWidth: 880, maxHeight: 800)
            .background(FileBrowserColors.background)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(FileBrowserColors.border) }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.78))
            .preferredColorScheme(.dark)
            .tint(.cyan)
        #endif
    }

    @ViewBuilder
    func fileBrowserEntryRowStyle() -> some View {
        #if os(tvOS)
        self
            .listRowBackground(FileBrowserColors.row)
        #else
        self
            .listRowBackground(FileBrowserColors.row)
            .listRowSeparator(.hidden)
        #endif
    }

    @ViewBuilder
    func fileBrowserListStyle() -> some View {
        #if os(tvOS)
        self
            .listStyle(.plain)
            .background(FileBrowserColors.background)
        #else
        self
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(FileBrowserColors.background)
        #endif
    }

    @ViewBuilder
    func fileBrowserBackground() -> some View {
        self.background(FileBrowserColors.background)
    }

    @ViewBuilder
    func fileBrowserNavigationTitleStyle() -> some View {
        #if os(tvOS)
        self
        #else
        navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

enum FileBrowserColors {
    static let background = Color(red: 0.07, green: 0.10, blue: 0.20)
    static let row = Color(red: 0.10, green: 0.14, blue: 0.25)
    static let border = Color(red: 0.26, green: 0.32, blue: 0.44)
}
