//
//  CaptureSequenceView.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 6/8/25.
//

import SwiftUI
import AVFoundation

enum TimeUnit: String, CaseIterable, Identifiable {
    case milliseconds, seconds, minutes, hours
    var id: String { rawValue }
    func toSeconds(_ value: Double) -> TimeInterval {
        switch self {
        case .milliseconds: return max(value / 1000.0, 0.3)
        case .seconds: return value
        case .minutes: return value * 60
        case .hours: return value * 3600
        }
    }
    
    var range: ClosedRange<Double> {
        switch self {
        case .milliseconds: return 300...1000
        case .seconds: return 1...100
        case .minutes: return 1...60
        case .hours: return 1...24
        }
    }
    
    var step: Double {
        1
    }
    
    var formatted: String {
        switch self {
        case .milliseconds: return "ms"
        case .seconds: return "s"
        case .minutes: return "min"
        case .hours: return "h"
        }
    }
}

struct CaptureSequenceView: View {
    init(sequence: LapseSequence, onSaveSequence: ((LapseSequence) -> Void)? = nil) {
        _session = .init(wrappedValue: .init(sequence: sequence))
        self.onSaveSequence = onSaveSequence
    }
    
    var onSaveSequence: ((LapseSequence) -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    
    @StateObject var session: CaptureSequenceSession
    
    @State private var interval: Double = 1.0
    @State private var unit: TimeUnit = .seconds
    @State private var selectedCamera: AVCaptureDevice.Position = .back
    
    @State private var isRecording: Bool = false
    @State private var startCurrentRecording: Date?
    @State private var lastCaptureDate: Date?
    @State private var stopRecordDate: Date?
    @State private var previousRecordingDuration: TimeInterval = 0
    @State private var intervalAnchorDate: Date?
    @State private var accumulatedPausedDuration: TimeInterval = 0
    
    var recordingDuration: TimeInterval {
        var result = previousRecordingDuration
        
        if isRecording, let startCurrentRecording {
            result += Date().timeIntervalSince(startCurrentRecording)
        }
        
        return result
    }
    
    var nextCapture: Date {
        let intervalSec = unit.toSeconds(interval)
        let baseDate = intervalAnchorDate ?? lastCaptureDate ?? startCurrentRecording ?? Date()
        
        var paused = accumulatedPausedDuration
        if let stop = stopRecordDate, stop > baseDate {
            paused += Date().timeIntervalSince(stop)
        }
        
        // En lugar de devolver ahora + remaining,
        // devolvemos la fecha absoluta de la próxima captura
        return baseDate.addingTimeInterval(intervalSec + paused)
    }
    
    var nextCaptureCountdown: TimeInterval {
        let result = Date().distance(to: nextCapture)
        
        print("Next capture countdown: \(result)")
        
        return result
    }
    
    var body: some View {
        NavigationStack {
            VStack {
                CameraPreview(session: $session.session)
                    .frame(height: 400)
                VStack {
                    HStack {
                        Picker(String(localized: .CaptureSequence.camera), selection: $selectedCamera) {
                            Text(.CaptureSequence.back).tag(AVCaptureDevice.Position.back)
                            Text(.CaptureSequence.front).tag(AVCaptureDevice.Position.front)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedCamera) { _, newCamera in
                            session.updateCamera(to: newCamera)
                        }
                    }
                    HStack {
                        VStack {
                            Slider(value: $interval, in: unit.range, step: unit.step)
                            Text(
                                .CaptureSequence.interval(
                                    Int(interval),
                                    unit.formatted
                                )
                            )
                        }
                        Picker("", selection: $unit) {
                            ForEach(TimeUnit.allCases) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: unit) { _, newUnit in
                            interval = newUnit.range.lowerBound
                        }
                    }
                }
                .padding(.horizontal)
                Button(action: {
                    if isRecording {
                        isRecording = false
                        stopRecordDate = .now
                        previousRecordingDuration += startCurrentRecording?.distance(to: .now) ?? .zero
                        startCurrentRecording = nil
                    } else {
                        isRecording = true
                        if let stop = stopRecordDate {
                            accumulatedPausedDuration += Date().timeIntervalSince(stop)
                            stopRecordDate = nil
                        }
                        if intervalAnchorDate == nil {
                            intervalAnchorDate = lastCaptureDate ?? .now
                        }
                        startCurrentRecording = .now
                        if lastCaptureDate == nil {
                            takePhoto()
                        }
                    }
                }, label: {
                    Image(systemName: isRecording ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding()
                        .glassEffect(.regular.tint(isRecording ? .red : .green).interactive())
                })
                
                Text(.CaptureSequence.captures(session.sequence.count))
                DisplayedTextView {
                    .CaptureSequence.elapsedTime(formatElapsedTime(recordingDuration))
                }
                DisplayedTextView {
                    .CaptureSequence.nextCapture(String(format: "%.1f", nextCaptureCountdown))
                }
                
                if isRecording {
                    Text(.CaptureSequence.recording)
                        .foregroundColor(.red)
                }
                
                Spacer()
            }
            .navigationTitle(.CaptureSequence.new)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(.Common.close, systemImage: "xmark") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button(.Common.save, systemImage: "checkmark") {
                        onSaveSequence?(session.sequence)
                        dismiss()
                    }
                }
            }
            .onDisplayLinkUpdate {
                if nextCaptureCountdown <= 0, isRecording {
                    takePhoto()
                }
            }
        }
    }
    
    private func takePhoto() {
        session.takePhoto()
        lastCaptureDate = .now
        intervalAnchorDate = lastCaptureDate
        accumulatedPausedDuration = 0
    }
    
    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct CameraPreview: UIViewRepresentable {
    @Binding var session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        if let layer = uiView.layer.sublayers?.first as? AVCaptureVideoPreviewLayer {
            layer.session = session
            layer.frame = uiView.bounds
        }
    }
}

class CaptureSequenceSession: NSObject, ObservableObject {
    let sequence: LapseSequence
    @Published var session = AVCaptureSession()
    
    private let photoOutput = AVCapturePhotoOutput()
    
    init(sequence: LapseSequence) {
        self.sequence = sequence
        super.init()
        
        addVideoInput()
        addPhtotOutput()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }
    
    private func addVideoInput(position: AVCaptureDevice.Position = .back) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { return }
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) {
            session.addInput(input)
        }
    }
    
    private func addPhtotOutput() {
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }
    
    func updateCamera(to position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        addVideoInput(position: position)
        session.commitConfiguration()
    }
    
    func takePhoto() {
        photoOutput.capturePhoto(with: .init() /*TODO: Revisar este settings*/ , delegate: self)
    }
}

extension CaptureSequenceSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            print("Error al procesar la foto: \(error.localizedDescription)")
            return
        }
        
        guard let data = photo.fileDataRepresentation() else {
            print("No se pudo obtener la representación de los datos de la imagen")
            return
        }
        
        do {
            let capture = try CustomFileManager.shared.savePhoto(data, to: sequence)
            sequence.addCapture(capture)
        } catch {
            print("❌ Error al guardar la imagen: \(error.localizedDescription)")
        }
    }
}

#Preview {
    NavigationStack {
        CaptureSequenceView(sequence: .mock)
    }
}
