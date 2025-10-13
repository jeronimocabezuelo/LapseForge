//
//  CaptureSequenceSession.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 13/10/25.
//

import AVFoundation
import Combine

class CaptureSequenceSession: NSObject, ObservableObject {
    let sequence: LapseSequence
    
    @Published var interval: Double = 1.0
    @Published var unit: TimeUnit = .seconds
    @Published var selectedCamera: AVCaptureDevice.Position = .back
    
    @Published var isRecording: Bool = false
    @Published var startCurrentRecording: Date?
    @Published var lastCaptureDate: Date?
    @Published var stopRecordDate: Date?
    @Published var previousRecordingDuration: TimeInterval = 0
    @Published var intervalAnchorDate: Date?
    @Published var accumulatedPausedDuration: TimeInterval = 0
    
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
        
        //        print("Next capture countdown: \(result)")
        
        return result
    }
    
    func playPauseTapped() {
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
    }
    
    @Published var session = AVCaptureSession()
    
    private let photoOutput = AVCapturePhotoOutput()
    private var cancellables = Set<AnyCancellable>()
    
    init(sequence: LapseSequence) {
        self.sequence = sequence
        super.init()
        
        addVideoInput()
        addPhtotOutput()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
        
        // Suscripción a eventos del iPhone (o Watch si esta clase vive en iPhone)
        PhoneConnectivityManager.shared.lastReceivedPayloadSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] payload in
                guard let self else { return }
                if let event = payload["event"] as? String {
                    switch event {
                    case "captureTapped":
                        self.playPauseTapped()
                    default:
                        break
                    }
                }
            }
            .store(in: &cancellables)
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
        
        lastCaptureDate = .now
        intervalAnchorDate = lastCaptureDate
        accumulatedPausedDuration = 0
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
