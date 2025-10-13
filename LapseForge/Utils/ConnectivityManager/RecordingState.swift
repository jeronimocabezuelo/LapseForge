//
//  RecordingState.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 13/10/25.
//

import Foundation

let loggingEnabled = true

/// A typed snapshot of the current recording state to send to the Watch.
struct RecordingState: Codable {
    let isRecording: Bool
    let capturesCount: Int
    let duration: TimeInterval
}
