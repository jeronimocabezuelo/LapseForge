//
//  CaptureSequenceSession.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 13/10/25.
//

import AVFoundation
import Combine
import CoreImage
import UIKit.UIImage

enum CaptureSequenceCamera {
    case front
    case back
    
    fileprivate var position: AVCaptureDevice.Position {
        switch self {
        case .front: return .front
        case .back: return .back
        }
    }
}

enum CaptureSequencePreset: String, CaseIterable, Identifiable {
    case hd4k
    case hd1080p
    case hd720p
    case sd
    
    var id: String { self.rawValue }
    
    fileprivate var preset: AVCaptureSession.Preset {
        switch self {
        case .hd4k: return .hd4K3840x2160
        case .hd1080p: return .hd1920x1080
        case .hd720p: return .hd1280x720
        case .sd: return .vga640x480
        }
    }
    
    var name: String {
        switch self {
        case .hd4k: return "4K"
        case .hd1080p: return "1080p"
        case .hd720p: return "720p"
        case .sd: return "SD"
        }
    }
}

class CaptureSequenceSession: NSObject, ObservableObject {
    let sequence: LapseSequence
    
    @Published var interval: Double = 1.0
    @Published var unit: TimeUnit = .seconds
    
    @Published var selectedCamera: CaptureSequenceCamera = .back
    @Published var selectedPreset: CaptureSequencePreset = .hd4k
    @Published var zoomFactor: CGFloat = 1.0
    var minZoomFactor: CGFloat = 1.0
    var maxZoomFactor: CGFloat = 1.0
    @Published var torchEnabled: Bool = false
    
    var zoomRange: ClosedRange<CGFloat> { minZoomFactor...maxZoomFactor }
    
    @Published var isRecording: Bool = false
    @Published var startCurrentRecording: Date?
    @Published var lastCaptureDate: Date?
    @Published var stopRecordDate: Date?
    @Published var previousRecordingDuration: TimeInterval = 0
    @Published var intervalAnchorDate: Date?
    @Published var accumulatedPausedDuration: TimeInterval = 0
    
    var waitingImageReply: Bool = false
    
    var availablePresets: [CaptureSequencePreset] {
        return CaptureSequencePreset.allCases.filter({ session.canSetSessionPreset($0.preset)})
    }
    
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
    private let videoOutput = AVCaptureVideoDataOutput()
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var cancellables = Set<AnyCancellable>()
    
    private var ticker: AnyCancellable?
    private var lastSentElapsed: Int = -1
    private var lastSentNextCaptureIn: Int = -1
    
    init(sequence: LapseSequence) {
        self.sequence = sequence
        super.init()
        
        addVideoInput()
        addPhotoOutput()
        addVideoOutput()
        createRotationCoordinator()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
        
        $zoomFactor
            .removeDuplicates()
            .sink { [weak self] newValue in self?.updateZoom(newValue)
            }
            .store(in: &cancellables)
        
        $torchEnabled
            .removeDuplicates()
            .sink { [weak self] newValue in self?.updateTorch(newValue)
            }
            .store(in: &cancellables)
        
        // Suscripción a eventos del iPhone (o Watch si esta clase vive en iPhone)
        WatchConnectivityManager.shared.receivedMessageSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self else { return }
                switch message {
                case .isRecording(let isRecording):
                    guard  isRecording != self.isRecording else { return }
                    playPauseTapped()
                default: break
                }
            }
            .store(in: &cancellables)
        
        // On-change: isRecording -> snapshot inmediato y arrancar/parar ticker
        $isRecording
            .removeDuplicates()
            .sink { [weak self] recording in
                guard let self else { return }
                if recording {
                    self.startSnapshotTicker()
                } else {
                    self.stopSnapshotTicker()
                }
                self.sendSnapshotToWatch(isRecording: recording)
            }
            .store(in: &cancellables)
        
        // On-change: cambios de intervalo o unidad -> snapshot
        Publishers.CombineLatest($interval.removeDuplicates(),
                                 $unit.removeDuplicates())
        .sink { [weak self] _, _ in
            self?.sendSnapshotToWatch()
        }
        .store(in: &cancellables)
        
        // On-change: nueva captura (sequence.count cambia) -> snapshot
        // Si LapseSequence expone count como propiedad, puedes observar con un publisher propio.
        // Si no, tras cada takePhoto/guardar, llamamos a sendSnapshotToWatch() manualmente.
        // Para ahora, lo llamamos al final de takePhoto() y en el delegado cuando se añade la captura.
    }
    
    private func sendSnapshotToWatch(throttled: Bool = false, isRecording overrideIsRecording: Bool? = nil) {
        let effectiveIsRecording = overrideIsRecording ?? self.isRecording
        
        // Redondeamos a segundos para evitar enviar cambios mínimos
        let elapsedRounded = Int(recordingDuration.rounded())
        let nextRounded = Int(max(0, nextCaptureCountdown).rounded())
        
        if throttled {
            // Si no cambió nada respecto al último envío, no mandamos
            if elapsedRounded == lastSentElapsed && nextRounded == lastSentNextCaptureIn {
                return
            }
        }
        
        lastSentElapsed = elapsedRounded
        lastSentNextCaptureIn = nextRounded
        
        let state = RecordingState(
            isRecording: effectiveIsRecording,
            capturesCount: sequence.count,
            duration: recordingDuration
        )
        WatchConnectivityManager.shared.send(message: .state(state))
    }
    
    private func addVideoInput() {
        let preset = selectedPreset.preset
        session.sessionPreset = preset
        
        let position = selectedCamera.position

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { return }
        
        updateZoomLimits(device: device)
        
        guard let input = try? AVCaptureDeviceInput(device: device) else { return }
        if session.canAddInput(input) {
            session.addInput(input)
        }
    }
    
    func updateZoomLimits(device: AVCaptureDevice) {
        minZoomFactor = device.minAvailableVideoZoomFactor
        maxZoomFactor = min(device.maxAvailableVideoZoomFactor, 5)
        
        // Clamp current zoomFactor to new limits
        if zoomFactor < minZoomFactor {
            zoomFactor = minZoomFactor
        } else if zoomFactor > maxZoomFactor {
            zoomFactor = maxZoomFactor
        }
    }
    
    private func addPhotoOutput() {
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
    }
    
    private func addVideoOutput() {
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "video_frame_queue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
    }
    
    private func createRotationCoordinator(position: AVCaptureDevice.Position = .back) {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position) else { return }
        
        rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    }
    
    private func startSnapshotTicker() {
        guard ticker == nil else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.sendSnapshotToWatch(throttled: true)
            }
    }
    
    private func stopSnapshotTicker() {
        ticker?.cancel()
        ticker = nil
        // Reset dedupe si quieres
        lastSentElapsed = -1
        lastSentNextCaptureIn = -1
    }
    
    func updateCamera() {
        session.beginConfiguration()
        session.inputs.forEach { session.removeInput($0) }
        addVideoInput()
        session.commitConfiguration()
    }
    
    private func updateZoom(_ zoom: CGFloat? = nil) {
        let zoomFactor = zoom ?? zoomFactor
        
        guard let videoInput = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.hasMediaType(.video) }) else { return }
        
        let device = videoInput.device
        let newZoomFactor = min(max(zoomFactor, minZoomFactor), maxZoomFactor)
        
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = newZoomFactor
            device.unlockForConfiguration()
        } catch {
            print("Failed to lock device for configuration: \(error.localizedDescription)")
        }
    }
    
    private func updateTorch(_ enabled: Bool? = nil) {
        let torchEnabled = enabled ?? torchEnabled
        
        guard let videoInput = session.inputs.compactMap({ $0 as? AVCaptureDeviceInput }).first(where: { $0.device.hasMediaType(.video) }) else { return }
        
        let device = videoInput.device
        
        if device.hasTorch {
            do {
                try device .lockForConfiguration()
                device.torchMode = torchEnabled ? .on : .off
                device.unlockForConfiguration()
            } catch {
                print("Failed to lock device for configuration: \(error.localizedDescription)")
            }
        }
    }
    
    func takePhoto() {
        photoOutput.capturePhoto(with: .init() /*TODO: Revisar este settings*/ , delegate: self)
        
        lastCaptureDate = .now
        intervalAnchorDate = lastCaptureDate
        accumulatedPausedDuration = 0
        
        // Snapshot inmediato tras captura
        sendSnapshotToWatch()
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
            
            // snapshot porque cambió capturesCount
            sendSnapshotToWatch()
        } catch {
            print("❌ Error al guardar la imagen: \(error.localizedDescription)")
        }
    }
}

extension CaptureSequenceSession: AVCaptureVideoDataOutputSampleBufferDelegate {
        func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
            guard !waitingImageReply else { return }
            
            guard WatchConnectivityManager.shared.isReachable else {
                print("Watch not reachable")
                return
            }
            
            waitingImageReply = true
            
            guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                print("No imageBuffer")
                waitingImageReply = false
                return
            }
    
            let ciImage = CIImage(cvPixelBuffer: imageBuffer)
            let orientedImage: CIImage
    
            if let coordinator = rotationCoordinator {
                let angleDegrees = coordinator.videoRotationAngleForHorizonLevelCapture
                let radians = CGFloat(angleDegrees) * .pi / 180
                let rotation = CGAffineTransform(rotationAngle: -radians)
    
                orientedImage = ciImage.transformed(by: rotation)
            } else {
                orientedImage = ciImage // Fallback: no rotation
            }
    
            let context = CIContext()
    
            guard let cgImage = context.createCGImage(orientedImage, from: orientedImage.extent) else {
                print("Failed to create CGImage")
                waitingImageReply = false
                return
            }
            let originalImage = UIImage(cgImage: cgImage)
            let downgradeImage = originalImage.resized(to: .custom(maxDimension: 80))
    
            guard let imageData = downgradeImage?.jpegData(maxMB: 0.05) else {
                print("No imageData")
                waitingImageReply = false
                return
            }
            
            print("Sending Image with \(imageData.count)")
            
            WatchConnectivityManager.shared.sendData(
                imageData,
                reply: { replyMessage in
                    print("reply: \(replyMessage)")
                    self.waitingImageReply = false
                },
                failure: { error in
                    print("error: \(error.localizedDescription)")
                    self.waitingImageReply = false
                }
            )
        }
}
