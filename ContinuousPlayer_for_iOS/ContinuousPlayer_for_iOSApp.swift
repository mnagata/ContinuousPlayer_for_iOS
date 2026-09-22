//
//  ContinuousPlayer_for_iOSApp.swift
//  ContinuousPlayer_for_iOS
//
//  Created by 永田誠 on 2026/09/19.
//

import SwiftUI

@main
struct ContinuousPlayer_for_iOSApp: App {
    var body: some Scene {
        WindowGroup {
            if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--validate-") }) {
                ValidationView()
            } else {
                ContentView()
            }
        }
    }
}
