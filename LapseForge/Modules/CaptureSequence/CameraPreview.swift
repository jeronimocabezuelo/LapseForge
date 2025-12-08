//
//  CameraPreview.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 13/10/25.
//

import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    @Binding var session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
            let image = UIImageView(image: .cameraPlaceholder)
            view.addSubview(image)
            image.translatesAutoresizingMaskIntoConstraints = false
            
            image.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
            image.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
            image.leftAnchor.constraint(equalTo: view.leftAnchor).isActive = true
            image.rightAnchor.constraint(equalTo: view.rightAnchor).isActive = true
        } else {
            
            let previewLayer = AVCaptureVideoPreviewLayer(session: session)
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
        }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.session = session
            layer.frame = uiView.bounds
        }
    }
}
