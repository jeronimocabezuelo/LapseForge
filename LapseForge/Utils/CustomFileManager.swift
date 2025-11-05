//
//  CustomFileManager.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 10/8/25.
//

import Foundation
import ZIPFoundation

protocol SequenceProtocol: Identifiable<UUID> {
    associatedtype CaptureType: CaptureProtocol
}

protocol CaptureProtocol: Identifiable<UUID> {
    init()
}

class CustomFileManager {
    static let shared = CustomFileManager()
    
    private let fileManager = FileManager.default
    
    private init() {}
    
    func savePhoto<S: SequenceProtocol>(_ photo: Data, to sequence: S) throws -> S.CaptureType {
        guard let sequenceDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appending(path: sequence.directoryName)
        else {
            print("No se pudo generar la URL del archivo")
            throw FileManagerError.invalidDirectory
        }
        
        try fileManager.createDirectory(at: sequenceDirectory, withIntermediateDirectories: true)
        
        let capture = S.CaptureType()
        
        let url = sequenceDirectory.appendingPathComponent(capture.frameName)
        
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try photo.write(to: url)
        
        return capture
    }
    
    func getPhotoUrl(from sequence: LapseSequence, at index: Int) throws -> URL {
        guard let sequenceDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appending(path: sequence.directoryName)
        else {
            print("No se pudo generar la URL del archivo")
            throw FileManagerError.invalidDirectory
        }
        
        guard let capture = sequence.capture(at: index) else {
            print("No se pudo obtener la captura por el indice")
            throw FileManagerError.noPhotoAtIndex
        }
        let capturePath = sequenceDirectory.appendingPathComponent(capture.frameName)
        
        return capturePath
    }
    
    func getPhoto(from sequence: LapseSequence, at index: Int) throws -> Data {
        let capturePath = try getPhotoUrl(from: sequence, at: index)
        
        return try Data(contentsOf: capturePath)
    }
    
    func zip(from captures: [LapseCapture]) throws -> URL {
        guard let sequence = captures.first?.sequence else {
            throw FileManagerError.insufficientFiles
        }
        
        let zipUrl = fileManager.temporaryDirectory.appending(path: "\(sequence.directoryName).zip")
        
        let urls: [URL] = captures.compactMap({
            guard let sequence = $0.sequence else { return nil }
            do {
                let url = try getPhotoUrl(from: sequence, at: $0.index)
                return url
            } catch {
                print("No se pudo añadir una captura al Zip: \(error.localizedDescription)")
                return nil
            }
        })
        
        guard !urls.isEmpty else { throw FileManagerError.insufficientFiles }
        
        if fileManager.fileExists(atPath: zipUrl.path) {
            try fileManager.removeItem(at: zipUrl)
        }
        
        // 3) Crear zip y añadir entradas
        let archive = try Archive(url: zipUrl, accessMode: .create)
        
        for url in urls {
            let fileName = url.lastPathComponent
            
            try archive.addEntry(with: fileName, fileURL: url)
        }
        
        return zipUrl
    }
    
    func removeUnusedPhotos(keeping projects: [LapseProject]) throws {
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw FileManagerError.invalidDirectory
        }
        
        let allSequences = projects.flatMap { $0.sequences }
        let usedDirectories = Set(allSequences.map { $0.directoryName })
        
        // --- 1. Directorios huérfanos ---
        try fileManager.contentsOfDirectory(at: documentsURL, includingPropertiesForKeys: nil)
            .filter(\.hasDirectoryPath)
            .filter { !usedDirectories.contains($0.lastPathComponent) }
            .forEach { url in
                try fileManager.removeItem(at: url)
                print("Removed unused directory: \(url.lastPathComponent)")
            }
        
        // --- 2. Capturas inválidas dentro de directorios válidos ---
        try allSequences.forEach { sequence in
            let sequenceDir = documentsURL.appendingPathComponent(sequence.directoryName)
            guard fileManager.fileExists(atPath: sequenceDir.path) else { return }
            
            let validCaptures = Set(sequence.captures.map { $0.frameName })
            try fileManager.contentsOfDirectory(at: sequenceDir, includingPropertiesForKeys: nil)
                .filter { !validCaptures.contains($0.lastPathComponent) }
                .forEach { url in
                    try fileManager.removeItem(at: url)
                    print("Removed unused capture: \(url.lastPathComponent) in \(sequence.directoryName)")
                }
        }
        
        // --- 3. Carpeta temporal (solo .mp4) ---
        let tempURL = fileManager.temporaryDirectory
        try fileManager.contentsOfDirectory(at: tempURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "mp4" }
            .forEach { url in
                try fileManager.removeItem(at: url)
                print("Removed temp mp4: \(url.lastPathComponent)")
            }
    }
}

enum FileManagerError: Error {
    case invalidDirectory
    case noPhotoAtIndex
    case insufficientFiles
}
