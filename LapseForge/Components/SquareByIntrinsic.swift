//
//  SquareByIntrinsic.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 4/10/25.
//

import SwiftUI

private struct SquareByIntrinsicModifier: ViewModifier {
    @State private var side: CGFloat?
    
    var contentMode: ContentMode = .fill

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { updateSize(proxy.size) }
                        .onChange(of: proxy.size) { _, newSize in
                            updateSize(newSize)
                        }
                }
            )
            .frame(width: side, height: side)
    }

    private func updateSize(_ size: CGSize) {
        let s: CGFloat?
        if size.width.isFinite && size.height.isFinite {
            switch contentMode {
            case .fit:
                s = min(size.width, size.height)
            case .fill:
                s = max(size.width, size.height)
            }
        } else if size.width.isFinite {
            s = size.width
        } else if size.height.isFinite {
            s = size.height
        } else {
            s = nil
        }
        if side != s { side = s }
    }
}

extension View {
    func squareByIntrinsic(contentMode: ContentMode = .fill) -> some View {
        modifier(SquareByIntrinsicModifier(contentMode: contentMode))
    }
}
