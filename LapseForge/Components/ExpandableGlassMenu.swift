//
//  ExpandableGlassMenu.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 5/10/25.
//

import SwiftUI

struct ExpandableGlassMenu<Content: View, Label: View>: View {
    var cornerRadius: CGFloat = 30
    var animation: Animation = .bouncy(duration: 0.5, extraBounce: 0.02)
    @ViewBuilder var label: Label
    @ViewBuilder var content: Content
    
    @State private var progress: CGFloat = .zero
    @State private var labelSize: CGSize = .zero
    @State private var contentSize: CGSize = .zero
    
    var labelOpacity: CGFloat {
        min(progress/0.35, 1)
    }
    
    var contentOpacity: CGFloat {
        max(0, progress - 0.35) / 0.65
    }
    
    var contentScale: CGFloat {
        let minAspectScale = min(labelSize.width / contentSize.width, labelSize.height / contentSize.height)
        return minAspectScale + (1 - minAspectScale) * progress
    }
    
    var blurProgress: CGFloat {
        progress > 0.5 ? (1 - progress) / 0.5 : progress / 0.5
    }
    
    var body: some View {
        GlassEffectContainer {
            let widthDiff = contentSize.width - labelSize.width
            let heightDiff = contentSize.height - labelSize.height
            
            let rWidth = widthDiff * contentOpacity
            let rHeight = heightDiff * contentOpacity
            
            ZStack {
                content
                    .compositingGroup()
                    .scaleEffect(contentScale)
                    .blur(radius: 14 * blurProgress)
                    .opacity(contentOpacity)
                    .onGeometryChange(
                        for: CGSize.self,
                        of: { $0.size },
                        action: { contentSize = $0 }
                    )
                    .fixedSize()
                    .frame(
                        width: labelSize.width + rWidth,
                        height: labelSize.height + rHeight
                    )
                label
                    .contentShape(.rect)
                    .compositingGroup()
                    .blur(radius: 14 * blurProgress)
                    .opacity(1 - labelOpacity)
                    .onGeometryChange(
                        for: CGSize.self,
                        of: { $0.size },
                        action: { labelSize = $0 }
                    )
                    .fixedSize()
                    .frame(width: labelSize.width, height: labelSize.height)
                    .onTapGesture {
                        withAnimation(animation) {
                            progress = 1
                        }
                    }
                    .contentShape(.rect)
                    .allowsHitTesting(progress == 0)
            }
            .compositingGroup()
            .clipShape(.rect(cornerRadius: cornerRadius))
            .glassEffect(
                .regular.interactive(progress == 0),
                in: .rect(cornerRadius: cornerRadius)
            )
        }
        .onTapOutside {
            withAnimation(animation) {
                progress = 0
            }
        }
    }
}
