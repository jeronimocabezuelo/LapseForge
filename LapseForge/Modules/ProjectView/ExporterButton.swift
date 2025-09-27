//
//  ExportView.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 1/9/25.
//

import SwiftUI
import AVFoundation
import Photos

struct ExporterButton: View {
    @ObservedObject
    var exporter: Exporter
    
    var project: LapseProject
    
    var body: some View {
        Button(.Project.exportButtonTitle) {
            Task {
                do {
                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("export.mp4")
                    try await exporter.exportLapse(project: project, fileUrl: tempURL)
                    try await saveVideoToGallery(from: tempURL)
                    
                    try await Task.sleep(for: .seconds(4))
                } catch {
                    print("Export error: \(error)")
                }
            }
        }
    }
    
    func saveVideoToGallery(from url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        
        guard status == .authorized else {
            throw NSError(domain: "Not authorized", code: -1, userInfo: nil)
        }
        
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
        
        try FileManager.default.removeItem(at: url)
        
        runOnMainThread {
            exporter.status = .success
        }
    }
}

enum ExportStatus {
    case creatingSubvideos(progress: Double)
    case unifying(progress: Double)
    case exporting(progress: Double)
    
    case exported
    case success
    
    var currentTitle: LocalizedStringResource {
        switch self {
        case .creatingSubvideos:
            return .ProjectsList.creatingSubvideos
        case .unifying:
            return .ProjectsList.unifying
        case .exporting, .exported, .success:
            return .ProjectsList.exporting
        }
    }
    
    var currentValue: Double {
        switch self {
        case .creatingSubvideos(progress: let progress):
            return progress
        case .unifying(progress: let progress):
            return progress
        case .exporting(progress: let progress):
            return progress
        case .exported, .success:
            return 1
        }
    }
    
    var totalValue: Double {
        switch self {
        case .creatingSubvideos(let progress):
            return progress/3
        case .unifying(let progress):
            return 1/3 + progress/3
        case .exporting(let progress):
            return 2/3 + progress/3
        case .exported, .success:
            return 1
        }
    }
}

class Exporter: ObservableObject {
    private let writerQueue = DispatchQueue(label: "mediaInputQueue")
    
    @Published
    var status: ExportStatus?
    
    func exportLapse(project: LapseProject, fps: Int = 30, fileUrl: URL) async throws {
        runOnMainThread {
            self.status = .creatingSubvideos(progress: .zero)
        }
        
        let frameTimes = project.frameTimes(fps: fps)
        let size = project.frameSize(times: frameTimes)
        
        var partsUrl: [URL] = []
        let chunks = frameTimes.chunked(into: 10)
        // Idea: paralelizar este proceso
        for (index, chunk) in chunks.enumerated() {
            let partURL = FileManager.default.temporaryDirectory.appendingPathComponent("export_part_\(index).mp4")
            try await exportLapse(project: project, fps: fps, frameTimes: chunk, size: size, at: partURL)
            
            partsUrl.append(partURL)
            runOnMainThread {
                if case .creatingSubvideos(let progress) = self.status {
                    self.status = .creatingSubvideos(progress: progress + 1/Double(chunks.count))
                }
            }
        }
        
        try await unifyViedos(at: partsUrl, outputURL: fileUrl)
        
        try FileManager.default.removeItems(at: partsUrl)
    }
    
    func exportLapse(project: LapseProject, fps: Int = 30, frameTimes: [TimeInterval], size: CGSize, at fileUrl: URL) async throws {
        let cgImages: [CGImage] = frameTimes.compactMap { time in
            autoreleasepool {
                guard let data = project.captureData(at: time),
                      let ui = UIImage(data: data) else { return nil }
                let normalized = ui.normalized.resized(to: size)
                return normalized.cgImage
            }
        }
        
        guard frameTimes.count == cgImages.count else {
            throw NSError(domain: "Error exporting video: number of frames does not match number of images", code: -1, userInfo: nil)
        }
        
        let frameDuration = CMTime(seconds: 1.0 / Double(fps), preferredTimescale: 600)
        
        try await createVideo(cgImages, at: fileUrl, frameDuration: frameDuration)
    }
    
    func createVideo(_ frames: [CGImage], at fileUrl: URL, frameDuration: CMTime) async throws {
        try await withCheckedThrowingContinuation { continuation in
            createVideo(frames, at: fileUrl, frameDuration: frameDuration) { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    enum CreateVideoResult {
        case success
        case failure(Error)
    }
    
    func createVideo(_ frames: [CGImage], at fileUrl: URL, frameDuration: CMTime, completion: ((CreateVideoResult) -> Void)?) {
        do {
            let context = try prepareVideoWriter(frames: frames, fileUrl: fileUrl, frameDuration: frameDuration)
            writeFrames(context: context,
                        frames: frames,
                        completion: completion)
        } catch {
            completion?(.failure(error))
        }
    }
    
    /// Prepara el AVAssetWriter, input, adaptor y frameDuration. Devuelve nil si falla algo.
    private func prepareVideoWriter(frames: [CGImage], fileUrl: URL, frameDuration: CMTime) throws -> VideoWriterContext {
        if FileManager.default.fileExists(atPath: fileUrl.path) {
            try FileManager.default.removeItem(at: fileUrl)
        }
        
        guard let width = frames.first?.width, let height = frames.first?.height else {
            throw NSError(domain: "Error exporting video: width and height not found", code: -1, userInfo: nil)
        }
        
        let avOutputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: Float(width)),
            AVVideoHeightKey: NSNumber(value: Float(height)),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        
        guard let assetWriter = try? AVAssetWriter(outputURL: fileUrl, fileType: AVFileType.mp4) else {
            throw NSError(domain: "Error exporting video: AVAssetWriter creation failed", code: -1, userInfo: nil)
        }
        
        guard assetWriter.canApply(outputSettings: avOutputSettings, forMediaType: AVMediaType.video) else {
            throw NSError(domain: "Error exporting video: Cannot apply output setting.", code: -1, userInfo: nil)
        }
        
        let assetWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: avOutputSettings)
        assetWriterInput.expectsMediaDataInRealTime = false
        
        guard assetWriter.canAdd(assetWriterInput) else {
            throw NSError(domain: "Error exporting video: Cannot add writer input.", code: -1, userInfo: nil)
        }
        assetWriter.add(assetWriterInput)
        
        // The pixel buffer adaptor must be created before writing
        let sourcePixelBufferAttributesDictionary = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: NSNumber(value: Float(width)),
            kCVPixelBufferHeightKey as String: NSNumber(value: Float(height))
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: assetWriterInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary
        )
        
        guard assetWriter.startWriting() else {
            throw NSError(domain: "Error exporting video: Cannot starting writing.", code: -1, userInfo: nil)
        }
        
        // start writing session
        assetWriter.startSession(atSourceTime: CMTime.zero)
        
        return VideoWriterContext(writer: assetWriter, input: assetWriterInput, adaptor: pixelBufferAdaptor, frameDuration: frameDuration)
    }
    
    /// Escribe los frames usando el writer/input/adaptor y llama completion cuando termina.
    private func writeFrames(context: VideoWriterContext,
                             frames: [CGImage],
                             completion: ((CreateVideoResult) -> Void)?) {
        var frameCount = 0
        var frameBuffers = frames.map { $0.cvPixelBuffer }
        
        context.input.requestMediaDataWhenReady(on: writerQueue) {
            while !frameBuffers.isEmpty {
                if context.input.isReadyForMoreMediaData == false {
                    print("more buffers need to be written.")
                    break
                }
                
                guard let buffer = frameBuffers.removeFirst() else {
                    print("nil buffer on frame \(frameCount)")
                    continue
                }
                let presentationTime = CMTimeMultiply(context.frameDuration, multiplier: Int32(frameCount))
                let success = context.adaptor.append(buffer, withPresentationTime: presentationTime)
                if !success {
                    print("fail to add image at frame count \(frameCount)")
                    continue
                }
                frameCount += 1
            }
            
            if frameBuffers.isEmpty {
                context.input.markAsFinished()
                context.writer.finishWriting {
                    let status = context.writer.status
                    let error = context.writer.error
                    DispatchQueue.main.async {
                        if status == .completed {
                            completion?(.success)
                        } else {
                            let err = error ?? NSError(domain: "Exporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "AVAssetWriter finished with status \(status.rawValue)"])
                            completion?(.failure(err))
                        }
                    }
                }
            }
        }
    }
    
    private func unifyViedos(at inputURLs: [URL], outputURL: URL) async throws {
        runOnMainThread {
            self.status = .unifying(progress: .zero)
        }
        // Borrar archivo de salida si ya existe
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        // Crear composición
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "Exporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear el track de composición"])
        }
        
        var currentTime = CMTime.zero
        
        // Insertar cada video en el track de composición
        for url in inputURLs {
            let asset = AVURLAsset(url: url)
            guard let assetTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw NSError(domain: "Exporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se encontró track de video en \(url)"])
            }
            
            let duration = try await asset.load(.duration)
            
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: currentTime)
            
            currentTime = CMTimeAdd(currentTime, duration)
            runOnMainThread {
                if case .unifying(let progress) = self.status {
                    self.status = .unifying(progress: progress + 1/Double(inputURLs.count))
                }
            }
        }
        
        // Crear sesión de exportación (intenta passthrough primero)
        var exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough)
        if exportSession == nil {
            exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
        }
        guard let exportSession else {
            throw NSError(domain: "Exporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear la sesión de exportación"])
        }
        exportSession.outputFileType = .mp4
        exportSession.shouldOptimizeForNetworkUse = true
        
        // Monitor de progreso de exportación
        let monitorTask = Task {
            for await _ in exportSession.states(updateInterval: 0.1) {
                runOnMainThread {
                    self.status = .exporting(progress: Double(exportSession.progress))
                }
            }
        }
        
        // Ejecutar la exportación y esperar al monitor
        defer { monitorTask.cancel() }
        try await exportSession.export(to: outputURL, as: .mp4)
        await monitorTask.value
        runOnMainThread {
            self.status = .exported
        }
    }
}

private struct VideoWriterContext {
    let writer: AVAssetWriter
    let input: AVAssetWriterInput
    let adaptor: AVAssetWriterInputPixelBufferAdaptor
    let frameDuration: CMTime
}

private extension LapseProject {
    func frameTimes(fps: Int = 30) -> [TimeInterval] {
        let totalFrames = Int(totalDuration * Double(fps))
        let frameTimes: [TimeInterval] = (0..<totalFrames).map { Double($0) / Double(fps) }
        return frameTimes
    }
    
    func frameSize(times: [TimeInterval]) -> CGSize {
        var maxWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
        
        for time in times {
            autoreleasepool {
                guard let data = captureData(at: time),
                      let image = UIImage(data: data) else { return }
                
                maxWidth = max(maxWidth, image.size.width)
                maxHeight = max(maxHeight, image.size.height)
            }
        }
        
        return CGSize(width: maxWidth, height: maxHeight)
    }
}

private extension UIImage {
    func resized(to targetSize: CGSize) -> UIImage {
        guard size != targetSize else { return self }
        
        let aspectWidth = targetSize.width / size.width
        let aspectHeight = targetSize.height / size.height
        let aspectRatio = min(aspectWidth, aspectHeight)
        
        let newSize = CGSize(width: size.width * aspectRatio,
                             height: size.height * aspectRatio)
        
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            UIColor.black.setFill()
            UIBezierPath(rect: CGRect(origin: .zero, size: targetSize)).fill()
            
            let x = (targetSize.width - newSize.width) / 2
            let y = (targetSize.height - newSize.height) / 2
            draw(in: CGRect(origin: CGPoint(x: x, y: y), size: newSize))
        }
    }
}

extension UIImage {
    var normalized: UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage ?? self
    }
}

private extension CGImage {
    var cvPixelBuffer: CVPixelBuffer? {
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        var pixelBuffer: CVPixelBuffer?
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            self.width,
            self.height,
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
        )
        let context = CGContext(
            data: pixelData,
            width: self.width,
            height: self.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: rgbColorSpace,
            bitmapInfo: bitmapInfo.rawValue)
        
        context?.draw(self, in: CGRect(x: 0, y: 0, width: self.width, height: self.height))
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        return pixelBuffer
        
    }
}

private extension ArraySlice {
    var array: [Element] {
        return Array(self)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

private extension FileManager {
    func removeItems(at urls: [URL]) throws {
        for url in urls where fileExists(atPath: url.path) {
            try self.removeItem(at: url)
        }
    }
}
