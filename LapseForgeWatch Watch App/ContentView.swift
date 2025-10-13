//
//  ContentView.swift
//  LapseForgeWatch Watch App
//
//  Created by Jerónimo Cabezuelo Ruiz on 12/10/25.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Button {
                WatchConnectivityManager.shared.send(
                    message: ["event": "captureTapped"]
                ) { reply in
                    print("Reply from iPhone:", reply)
                } error: { error in
                    print("WC error:", error.localizedDescription)
                }
            } label: {
                Text("Capturar")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
