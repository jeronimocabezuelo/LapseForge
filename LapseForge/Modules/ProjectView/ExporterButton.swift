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
            exporter.status?.success = true
        }
    }
}

struct ExportStatus {
    var exportProgress: Double = .zero
    var unifyProgress: Double = .zero
    var success: Bool = false
}

class Exporter: ObservableObject {
    private let writerQueue = DispatchQueue(label: "mediaInputQueue")
    
    @Published
    var status: ExportStatus?
    
    func exportLapse(project: LapseProject, fps: Int = 30, fileUrl: URL) async throws {
        runOnMainThread {
            self.status = .init()
        }
        
        let frameTimes = project.frameTimes(fps: fps)
        let size = project.frameSize(times: frameTimes)
        
        var partsUrl: [URL] = []
        let chunks = frameTimes.chunked(into: 10)
        // Idea: paralelizar este proceso
        for (index, chunk) in chunks.enumerated() {
            let partURL = FileManager.default.temporaryDirectory.appendingPathComponent("export_part_\(index).mp4")
            try await exportLapse(project: project, fps: fps, frameTimes: chunk, size: size, at: partURL)
            
            print("Part \(index) exportada.")
            partsUrl.append(partURL)
            runOnMainThread {
                self.status?.exportProgress += 1/Double(chunks.count)
            }
        }
        
        try await unifyViedos(at: partsUrl, outputURL: fileUrl)
        
        try FileManager.default.removeItems(at: partsUrl)
    }
    
    func exportLapse(project: LapseProject, fps: Int = 30, frameTimes: [TimeInterval], size: CGSize, at fileUrl: URL) async throws {
        let imagesData = frameTimes.compactMap({
            return project.captureData(at: $0)
        })
        let uiImages = imagesData.compactMap({
            return UIImage(data: $0)
        })
        let normalizedImages = uiImages.map({
            $0.normalized.resized(to: size)
        })
        let cgImages = normalizedImages.compactMap({
            return $0.cgImage
        })
        
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
            print("width and height not found")
            throw NSError(domain: "Error exporting video: width and height not found", code: -1, userInfo: nil)
        }
        
        let avOutputSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: NSNumber(value: Float(width)),
            AVVideoHeightKey: NSNumber(value: Float(height))
        ]
        
        guard let assetWriter = try? AVAssetWriter(outputURL: fileUrl, fileType: AVFileType.mp4) else {
            print("AVAssetWriter creation failed")
            throw NSError(domain: "Error exporting video: AVAssetWriter creation failed", code: -1, userInfo: nil)
        }
        
        guard assetWriter.canApply(outputSettings: avOutputSettings, forMediaType: AVMediaType.video) else {
            print("Cannot apply output setting.")
            throw NSError(domain: "Error exporting video: Cannot apply output setting.", code: -1, userInfo: nil)
        }
        
        let assetWriterInput = AVAssetWriterInput(mediaType: AVMediaType.video, outputSettings: avOutputSettings)
        
        guard assetWriter.canAdd(assetWriterInput) else {
            print("cannot add writer input")
            throw NSError(domain: "Error exporting video: Cannot add writer input.", code: -1, userInfo: nil)
        }
        assetWriter.add(assetWriterInput)
        
        // The pixel buffer adaptor must be created before writing
        let sourcePixelBufferAttributesDictionary = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange),
            kCVPixelBufferWidthKey as String: NSNumber(value: Float(width)),
            kCVPixelBufferHeightKey as String: NSNumber(value: Float(height))
        ]
        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: assetWriterInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributesDictionary
        )
        
        Thread.sleep(forTimeInterval: 0.2)
        
        guard assetWriter.startWriting() else {
            print("cannot starting writing")
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
                context.writer.finishWriting(completionHandler: {
                    print("writing finished")
                    DispatchQueue.main.async {
                        completion?(.success)
                        return
                    }
                })
            }
        }
    }
    
    private func unifyViedos(at inputURLs: [URL], outputURL: URL) async throws {
        print("Unificando \(inputURLs.count) videos")
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
            print("Añadiendo video \(url.lastPathComponent)")
            let asset = AVURLAsset(url: url)
            guard let assetTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw NSError(domain: "Exporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se encontró track de video en \(url)"])
            }
            
            let duration = try await asset.load(.duration)
            
            let timeRange = CMTimeRange(start: .zero, duration: duration)
            try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: currentTime)
            
            currentTime = CMTimeAdd(currentTime, duration)
            runOnMainThread {
                self.status?.unifyProgress += 1/Double(inputURLs.count)
            }
        }
        
        // Crear sesión de exportación
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "Exporter", code: -1, userInfo: [NSLocalizedDescriptionKey: "No se pudo crear la sesión de exportación"])
        }
        
        exportSession.shouldOptimizeForNetworkUse = true
        print("Exportando video unificado")
        try await exportSession.export(to: outputURL, as: .mp4)
        print("Exportado video unificado")
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
            kCVPixelFormatType_32ARGB,
            attributes,
            &pixelBuffer
        )
        
        guard status == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
        
        let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer)
        let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
        
        let context = CGContext(
            data: pixelData,
            width: self.width,
            height: self.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: rgbColorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
        
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
