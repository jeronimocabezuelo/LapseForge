//
//  IdleTimerDisabled.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 8/10/25.
//

import SwiftUI

private struct IdleTimerDisabledModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let isEnabled: Bool
    
    @State private var previousIdleTimerDisabled: Bool = false
    
    private func setIdleTimer(disabled: Bool) {
        if disabled && UIApplication.shared.isIdleTimerDisabled != true {
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
        }
        UIApplication.shared.isIdleTimerDisabled = disabled
    }
    
    private func restoreIdleTimerIfNeeded() {
        UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
    }
    
    func body(content: Content) -> some View {
        content
            .onChange(of: isEnabled) { _, enabled in
                if enabled {
                    setIdleTimer(disabled: true)
                } else {
                    restoreIdleTimerIfNeeded()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    if isEnabled { setIdleTimer(disabled: true) }
                case .inactive, .background:
                    break
                @unknown default:
                    break
                }
            }
            .onAppear {
                if isEnabled { setIdleTimer(disabled: true) }
            }
            .onDisappear {
                restoreIdleTimerIfNeeded()
            }
    }
}

extension View {
    func idleTimerDisabled(_ enabled: Bool) -> some View {
        modifier(IdleTimerDisabledModifier(isEnabled: enabled))
    }
}
