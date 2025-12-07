//
//  ConfigurationSequenceView.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 10/8/25.
//
import SwiftUI

struct ConfigurationSequenceView: View {
    var currentSequence: LapseSequence
    @Binding var catalogSequence: LapseSequence?
    
    var namespace: Namespace.ID
    
    @ViewBuilder
    var nameAndDate: some View {
        HStack {
            TextField(
                String(localized: .Project.unnamedSequence),
                text: Binding(
                    get: { currentSequence.title ?? "" },
                    set: { newValue in
                        currentSequence.title = newValue
                    }
                )
            )
            if let firstCapture = currentSequence.captures.first {
                Text(firstCapture.date, format: Date.FormatStyle(date: .long, time: .standard))
                    .font(.footnote)
            }
        }
    }
    
    @ViewBuilder
    var durationView: some View {
        VStack {
            Text(.Project.sequenceDuration)
            TimeIntervalPicker(
                timeInterval: .init(
                    get: {
                        currentSequence.expectedDuration
                    },
                    set: { new in
                        currentSequence.expectedDuration = new
                    }
                ),
                min: 5.0
            )
        }
    }
    
    @ViewBuilder
    var reversedButton: some View {
        CustomButton(
            action: {
                currentSequence.reversed.toggle()
            },
            systemImageName: "clock.arrow.circlepath",
            title: currentSequence.reversed ? .Project.reversed : .Project.normal
        )
    }
    
    @ViewBuilder
    var rotateButton: some View {
        CustomButton(
            action: {
                currentSequence.rotate()
            },
            systemImageName: "rotate.right",
            title: currentSequence.rotation.title
        )
    }
    
    @ViewBuilder
    var catalogButton: some View {
        CustomButton(
            action: {
                catalogSequence = currentSequence
            },
            systemImageName: "photo.stack",
            title: .Project.frameCatalog
        )
        .glassEffectID("catalog_transition", in: namespace)
        .matchedTransitionSource(id: "catalog_transition", in: namespace)
    }
    
    var body: some View {
        VStack {
            nameAndDate
            HStack(alignment: .top) {
                durationView
                VStack {
                    GlassEffectContainer {
                        reversedButton
                        rotateButton
                        catalogButton
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
    }
}

private struct CustomButton: View {
    var action: () -> Void
    var systemImageName: String
    var title: LocalizedStringResource
    
    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: systemImageName)
                Text(title)
                    .frame(maxWidth: .infinity)
            }
        }
        .controlSize(.large)
        .buttonStyle(.glass)
    }
}

#Preview {
    ConfigurationSequencePreview()
}

private struct ConfigurationSequencePreview: View {
    @Namespace private var namespace
    
    var body: some View {
        ConfigurationSequenceView(
            currentSequence: .mock,
            catalogSequence: .constant(nil),
            namespace: namespace
        )
    }
}
