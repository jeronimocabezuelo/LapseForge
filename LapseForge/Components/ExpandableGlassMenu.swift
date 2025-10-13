//
//  ExpandableGlassMenu.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 5/10/25.
//

import SwiftUI

/// ExpandableGlassMenu
///
/// Error conocido: el efecto glass queda cortado, eliminar el ``matchedTransitionSource(id: "ExpandableGlassMenu", in: namespace)`` soluciona el problema, pero se pierde la animación de zoom desde el propio botón.
/// Aunque hemos seguido este tutorial [iOS 26 Custom Menu Using SwiftUI | Xcode 26](https://www.youtube.com/watch?v=RwPsJhrPP9g) y a el no le ocurría. Puede ser un error de la RC de Xcode (versión con la que se ha compilado)
struct ExpandableGlassMenu<Label: View, Content: View>: View {
    var isHapticEnabled: Bool = true
    @ViewBuilder var label: Label
    @ViewBuilder var content: Content
    
    @State private var haptics: Bool = false
    @State private var isExpanded: Bool = false
    
    @Namespace var namespace
    
    var body: some View {
            label
                
                .onTapGesture {
                    if isHapticEnabled {
                        haptics.toggle()
                    }
                    
                    isExpanded.toggle()
                }
                .contentShape(.rect)
                .glassEffect(.regular.interactive(), in: .circle)
                .matchedTransitionSource(id: "ExpandableGlassMenu", in: namespace)
                .popover(
                    isPresented: $isExpanded,
                    content: {
                        PopoverHelper {
                            content
                        }
                        .glassEffectUnion(id: "ExpandableGlassMenu", namespace: namespace)
                        .navigationTransition(.zoom(sourceID: "ExpandableGlassMenu", in: namespace))
                    }
                )
                .sensoryFeedback(.selection, trigger: haptics)
        }
}

private struct PopoverHelper<Content: View>: View {
    @ViewBuilder var content: Content
    @State private var isVisible: Bool = false
    
    var body: some View {
        content
            .opacity(isVisible ? 1 : 0)
            .task {
                try? await Task.sleep(for: .seconds(0.1))
                withAnimation(.snappy(duration: 0.3, extraBounce: 0)) {
                    isVisible = true
                }
            }
            .presentationCompactAdaptation(.popover)
    }
}

#Preview {
    ScrollView(.vertical) {
        VStack(spacing: 25) {
            RoundedRectangle(cornerRadius: 30)
                .fill(.gray.opacity(0.2))
                .frame(height: 220)
            
            HStack {
                VStack(alignment: .leading) {
                    Text("Title")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                ExpandableGlassMenu(
                    label: {
                        Image(systemName: "chevron.right")
                            .font(.title3)
                            
                    },
                    content: {
                        VStack {
                            Text(.Project.newSequenceAlertTitle)
                            
                            Button(.Project.camera) {
                                print("camera")
                            }
                            Button(.Project.galery) {
                                print("galery")
                            }
                        }
                        .padding()
                        .buttonStyle(.bordered)
                    }
                )
            }
        }
        .padding(15)
        .padding(.bottom, 700)
    }
}
