//
//  LapseForgeWatchApp.swift
//  LapseForgeWatch Watch App
//
//  Created by Jerónimo Cabezuelo Ruiz on 12/10/25.
//

import SwiftUI

@main
struct LapseForgeWatch_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .task {
                    WatchConnectivityManager.shared.activate()
                }
        }
    }
}
