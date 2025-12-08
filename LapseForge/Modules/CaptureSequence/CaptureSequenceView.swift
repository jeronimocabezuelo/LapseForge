//
//  CaptureSequenceView.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 6/8/25.
//

import SwiftUI

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
    @State private var showSettings = false
    
    init(sequence: LapseSequence, onSaveSequence: ((LapseSequence) -> Void)? = nil) {
        _session = .init(wrappedValue: .init(sequence: sequence))
        self.onSaveSequence = onSaveSequence
    }
    
    var onSaveSequence: ((LapseSequence) -> Void)?
    
    @Environment(\.dismiss) private var dismiss
    
    @StateObject var session: CaptureSequenceSession
    
    @ViewBuilder
    var settingsMenu: some View {
        ExpandableGlassMenu(
            label: {
                Image(systemName: "gear")
                    .font(.title)
                    .squareByIntrinsic()
                    .padding()
            }, content: {
                VStack(spacing: 16) {
                    Picker(
                        String(localized: .CaptureSequence.camera),
                        selection: $session.selectedCamera
                    ) {
                        Text(.CaptureSequence.back).tag(CaptureSequenceCamera.back)
                        Text(.CaptureSequence.front).tag(CaptureSequenceCamera.front)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: session.selectedCamera) { _, _ in
                        session.updateCamera()
                    }
                    Picker("", selection: $session.selectedPreset) {
                        ForEach(session.availablePresets) { preset in
                            Text(preset.name).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: session.selectedPreset) { _, _ in
                        session.updateCamera()
                    }
                    HStack {
                        Text("Zoom \(session.zoomFactor, specifier: "%.2f")")
                        Slider(
                            value: $session.zoomFactor,
                            in: session.zoomRange
                        )
                    }
                    Toggle(.CaptureSequence.flash, isOn: $session.torchEnabled)
                }
                .padding()
            }
        )
    }
    
    @ViewBuilder
    var recordingView: some View {
        VStack {
            Button(action: {
                session.playPauseTapped()
            }, label: {
                Image(systemName: session.isRecording ? "pause.fill" : "play.fill")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                    .padding()
                    .squareByIntrinsic()
                    .glassEffect(.regular.tint(session.isRecording ? .red : .green).interactive())
            })
            
            Text(.CaptureSequence.captures(session.sequence.count))
            DisplayedTextView {
                .CaptureSequence.elapsedTime(formatElapsedTime(session.recordingDuration))
            }
            DisplayedTextView {
                .CaptureSequence.nextCapture(String(format: "%.1f", session.nextCaptureCountdown))
            }
            
            Text(session.isRecording ? .CaptureSequence.recording : " ")
                .foregroundColor(.red)
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 16))
    }
    var body: some View {
        NavigationStack {
            ZStack {
                CameraPreview(session: $session.session)
                    .ignoresSafeArea(edges: .bottom)
                recordingView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                settingsMenu
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                
                    .padding()
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
                if session.nextCaptureCountdown <= 0, session.isRecording {
                    session.takePhoto()
                }
            }
            .idleTimerDisabled(session.isRecording)
            .onDisappear {
                WatchConnectivityManager.shared.send(message: .reset)
            }
        }
    }
    
    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

#Preview {
    NavigationStack {
        CaptureSequenceView(sequence: .mock)
    }
}
