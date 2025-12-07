//
//  ImportSequenceView.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 29/8/25.
//

import SwiftUI
import AVFoundation

struct GeneratedSequence: SequenceProtocol {
    typealias CaptureType = GeneratedCapture
    let id: UUID = UUID()
    
    var captures: [GeneratedCapture] = []
}

struct GeneratedCapture: CaptureProtocol {
    let id: UUID = UUID()
    var index: Int = -1
}

struct ImportSequenceView: View {
    let url: URL?
    var onSaveSequence: ((LapseSequence) -> Void)
    
    @State private var asset: AVURLAsset?
    @State private var seconds: Double?
    @State private var fps: Double?
    @State private var framesToExtract: Double = 1
    @State private var extractedFrames: Int?
    @State private var startGeneration: Date?
    
    @Environment(\.dismiss) private var dismiss
    
    private var totalFrames: Int {
        guard let seconds, let fps else { return 1 }
        return max(1, Int(round(fps * seconds)))
    }
    
    private var estimatedDuration: String {
        let second = Int(round(framesToExtract / 60))
        let minutes = second / 60
        let secondPart = second % 60
        
        return "\(minutes > 0 ? "\(minutes) min" : "") \(secondPart)s"
    }
    
    private var remainingTime: String {
        guard let startGeneration,
              let extractedFrames,
              extractedFrames > 0 else { return "Calculando..." }
        
        let elapsedTime = Date().timeIntervalSince(startGeneration)
        let framesRemaining = framesToExtract - Double(extractedFrames)
        let estimatedRemaining = elapsedTime * framesRemaining / Double(extractedFrames)
        
        let minutes = Int(estimatedRemaining) / 60
        let seconds = Int(estimatedRemaining) % 60
        
        if minutes > 0 {
            return "\(minutes) min \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
    
    var body: some View {
        ZStack {
            NavigationStack {
                VStack {
                    Text(.ImportSequence.countFrames(totalFrames))
                    Text(.ImportSequence.selectionDescription)
                    if totalFrames <= 1 {
                        Text(.ImportSequence.onlyOneFrame)
                    } else {
                        Text(.ImportSequence.recount(Int(framesToExtract), totalFrames))
                        Slider(
                            value: $framesToExtract,
                            in: 1...Double(totalFrames),
                            step: 1
                        )
                        Text(.ImportSequence.estimatedTime(estimatedDuration))
                    }
                    Button(.ImportSequence.generateSequence) {
                        Task {
                            guard let generatedSequence = await generateSequence() else {
                                dismiss() // Se podría también mostrar un error
                                return
                            }
                            
                            await MainActor.run {
                                let sequence = LapseSequence(generatedSequence: generatedSequence)
                                onSaveSequence(sequence)
                                dismiss()
                            }
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(asset.isNull)
                }
                .padding()
                
            }
            if let extractedFrames {
                Spacer()
                    .background(.background.opacity(0.5))
                VStack(alignment: .leading) {
                    Text(.ImportSequence.generatingSequence)
                    ProgressView(value: Double(extractedFrames), total: framesToExtract)
                    Text(.ImportSequence.recount(extractedFrames, Int(framesToExtract)))
                    Text(.ImportSequence.remainingTime(remainingTime))
                }
                .padding(60)
                .background(.background)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(30)
                .shadow(radius: 16)
            }
        }
            .task {
                guard let url else {
                    dismiss()
                    return
                }
                asset = AVURLAsset(url: url)
                
                // 1) Cargar duración y track
                guard let duration = try? await asset?.load(.duration) else { return }
                guard let track = try? await asset?.loadTracks(withMediaType: .video).first else { return }
                
                // 2) Leer fps real (puede dar 0 en vídeo VFR)
                let fpsFloat = try? await track.load(.nominalFrameRate)
                fps = Double(max(1.0, fpsFloat ?? 0.0)) // si es 0, evitamos 0 fps
                seconds = duration.seconds
                framesToExtract = Double(totalFrames)
            }
    }
    
    func generateSequence() async -> GeneratedSequence? {
        guard let asset,
              let fps else { return nil }
       
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // exactitud: .zero -> más lento pero más exacto; poner tolerancias si quieres más velocidad
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter  = .zero
        // limita el tamaño si quieres (reduce uso memoria / CPU)
        // generator.maximumSize = CGSize(width: 1920, height: 1080)
        
        self.extractedFrames = 0
        self.startGeneration = .now
        let step = max(1, totalFrames / Int(framesToExtract))
        var result = GeneratedSequence()
        
        await withTaskGroup(of: GeneratedCapture?.self) { group in
            for i in 0..<Int(framesToExtract) {
                group.addTask {
                    
                    let time = CMTime(seconds: Double(i * step) / fps, preferredTimescale: 600)
                    do {
                        let image = try await generator.image(at: time).image
                        // Aquí guardarías la imagen o la convertirías en Data
                        let uiImage = UIImage(cgImage: image)
                        guard let data  = uiImage.jpegData(compressionQuality: 0.9) else {
                            print("Error frame \(i) al convertir a JPEG")
                            return nil
                        }
                        
                        var capture = try CustomFileManager.shared.savePhoto(data, to: result)
                        capture.index = i
                        
                        print("Generado el frame \(i)")
                        await MainActor.run {
                            self.extractedFrames? += 1
                        }
                        return capture
                    } catch {
                        print("Error frame \(i): \(error)")
                        return nil
                    }
                }
            }
            
            for await capture in group {
                if let capture {
                    result.captures.append(capture)
                }
            }
        }
        
        result.captures.sort { $0.index < $1.index }
        
        return result
    }
}

#Preview {
    ImportSequenceView(url: nil, onSaveSequence: {_ in})
}
