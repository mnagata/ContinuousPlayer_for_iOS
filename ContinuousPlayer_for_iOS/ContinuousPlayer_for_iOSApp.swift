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
                    #if targetEnvironment(macCatalyst)
                    .frame(minWidth: 640, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
                    .background(CatalystInitialWindowSizing().allowsHitTesting(false))
                    #endif
            }
        }
        #if targetEnvironment(macCatalyst)
        .defaultSize(width: 1280, height: 720)
        .windowResizability(.contentSize)
        #endif
    }
}
