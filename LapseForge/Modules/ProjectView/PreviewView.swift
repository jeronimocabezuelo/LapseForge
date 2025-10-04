//
//  PreviewView.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 9/8/25.
//

import SwiftUI

struct PreviewView: View {
    var project: LapseProject
    @Binding var scrubber: TimeInterval
    @Binding var isPlaying: Bool
    
    @State private var playbackTask: Task<Void, Never>?
    
    var body: some View {
        Color.gray
            .overlay {
                if let (sequence, index) = project.sequenceAndIndex(at: scrubber),
                   let capture = sequence.capture(at: index) {
                    CaptureView(
                        capture: capture,
                        scaleType: .fit
                    )
                } else {
                    Text(.Project.preview)
                        .foregroundColor(.white)
                        .bold()
                }
            }
            .overlay(alignment: .bottom) {
                HStack {
                    HStack {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .padding()
                            .squareByIntrinsic()
                            .onTapGesture(perform: togglePlayback)
                            .glassEffect(.regular.interactive())
                        Spacer(minLength: .zero)
                    }
                    Text(.Project.timeScrubber(scrubber.timeString, project.totalDuration.timeString))
                        .shadow(
                            color: .white.opacity(0.8),
                            radius: 2,
                            x: 1,
                            y: 1
                        )
                    
                    HStack {
                        Spacer(minLength: .zero)
                        Text("")
                    }
                }
                .padding()
            }
    }
    
    private func togglePlayback() {
        if isPlaying {
            stopPlayback()
        } else {
            startPlayback()
        }
    }
    
    private func startPlayback() {
        isPlaying = true
        playbackTask = Task { @MainActor in
            let start = scrubber
            let startTime = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(startTime)
                let newValue = start + elapsed
                if newValue >= project.totalDuration {
                    scrubber = project.totalDuration
                    stopPlayback()
                    break
                } else {
                    scrubber = newValue
                }
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }
    
    private func stopPlayback() {
        playbackTask?.cancel()
        playbackTask = nil
        isPlaying = false
    }
}
