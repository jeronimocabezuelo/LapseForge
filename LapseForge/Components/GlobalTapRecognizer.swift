//
//  GlobalTapRecognizer.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 5/10/25.
//

import SwiftUI

private struct GlobalTapRecognizer: UIViewRepresentable {
    var excludedFrame: CGRect
    var onTapOutside: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        context.coordinator.attachIfNeeded(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTapOutside = onTapOutside
        context.coordinator.excludedFrame = excludedFrame
        context.coordinator.attachIfNeeded(to: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.detach()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            excludedFrame: excludedFrame,
            onTapOutside: onTapOutside
        )
    }

    private  class ImmediateTouchGestureRecognizer: UIGestureRecognizer {
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
            super.touchesBegan(touches, with: event)
            if state == .possible {
                state = .recognized
            }
        }
        override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool { false }
        override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool { false }
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var excludedFrame: CGRect
        var onTapOutside: () -> Void
        private weak var gesture: ImmediateTouchGestureRecognizer?
        weak var window: UIWindow?

        init(excludedFrame: CGRect, onTapOutside: @escaping () -> Void) {
            self.excludedFrame = excludedFrame
            self.onTapOutside = onTapOutside
        }

        // Adjunta el/los recognizers si aún no están o si el window cambió
        func attachIfNeeded(to view: UIView) {
            guard let newWindow = view.window else { return }
            if newWindow !== window {
                attach(to: newWindow)
            }
        }

        private func attach(to newWindow: UIWindow) {
            // Si cambia de window o host, limpia primero
            if newWindow !== window {
                detach()
            }
            
            if gesture == nil {
                let gesture = ImmediateTouchGestureRecognizer(
                    target: self,
                    action: #selector(handleImmediate(_:))
                )
                newWindow.addGestureRecognizer(gesture)
                self.gesture = gesture
            }

            self.window = newWindow
        }

        // Elimina los recognizers del window actual
        func detach() {
            if let gesture = gesture,
               let window = window {
                window.removeGestureRecognizer(gesture)
            }
            gesture = nil
            window = nil
        }

        @objc func handleImmediate(_ sender: UIGestureRecognizer) {
            guard let window = sender.view as? UIWindow else { return }
            let location = sender.location(in: window)
            if excludedFrame.contains(location) { return }
            onTapOutside()
        }
    }
}

private struct TapOutsideRecognizerModifier: ViewModifier {
    let onTapOutside: () -> Void
    
    @State private var viewFrame: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GlobalTapRecognizer(
                    excludedFrame: viewFrame,
                    onTapOutside: onTapOutside
                )
            )
            .onGeometryChange(
                for: CGRect.self,
                of: { $0.frame(in: .global) },
                action: { viewFrame = $0 }
            )
    }
}

extension View {
    /// Adjunta un reconocedor de tap global (a nivel de ventana) usando GlobalTapRecognizer.
    /// - Parameter onTapOutside: Acción a ejecutar al detectar el toque global.
    func onTapOutside(_ onTapOutside: @escaping () -> Void) -> some View {
        self.modifier(TapOutsideRecognizerModifier(onTapOutside: onTapOutside))
    }
}
