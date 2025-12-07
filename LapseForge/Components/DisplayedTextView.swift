//
//  DisplayedTextView.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 27/9/25.
//

import SwiftUI

struct DisplayedTextView<S>: View where S: StringProtocol {
    var text: () -> S
    @State private var displayedText: S = ""
    var body: some View {
        
        Text(displayedText)
            .onAppear { displayedText = text() }
            .onDisplayLinkUpdate {
                displayedText = text()
            }
    }
}

extension DisplayedTextView where S == String {
    init(_ text: @escaping () -> LocalizedStringResource) {
        self.init { String(localized: text()) }
    }
}

class DisplayLinkObserver: ObservableObject {
    @Published var timestamp: CFTimeInterval = 0
    private var displayLink: CADisplayLink?
    
    init() {
        displayLink = CADisplayLink(target: self, selector: #selector(update))
        displayLink?.add(to: .main, forMode: .common)
    }
    
    @objc private func update(link: CADisplayLink) {
        timestamp = link.timestamp
    }
    
    deinit {
        displayLink?.invalidate()
    }
}

struct DisplayLinkModifier: ViewModifier {
    @StateObject private var displayLink = DisplayLinkObserver()
    var onUpdate: (() -> Void)
    
    func body(content: Content) -> some View {
        content
            .onChange(of: displayLink.timestamp) { _, _ in
                onUpdate()
            }
    }
}

extension View {
    func onDisplayLinkUpdate(_ perform: @escaping () -> Void) -> some View {
        modifier(DisplayLinkModifier(onUpdate: perform))
    }
}
