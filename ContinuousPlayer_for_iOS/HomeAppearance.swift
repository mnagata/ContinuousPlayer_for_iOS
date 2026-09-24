import SwiftUI

/// Shared home-screen palette for iPhone, iPad and Apple TV.
enum HomeAppearance {
    static var background: LinearGradient {
        LinearGradient(colors: [
            Color(red: 0.06, green: 0.09, blue: 0.26),
            Color(red: 0.08, green: 0.18, blue: 0.28),
            Color(red: 0.16, green: 0.09, blue: 0.30)
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
