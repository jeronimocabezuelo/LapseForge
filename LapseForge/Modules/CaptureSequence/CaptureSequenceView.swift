//
//  CaptureSequenceView.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 6/8/25.
//

import SwiftUI
import AVFoundation // Para las posibles cámaras TODO: Mover al sessión

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
    
    var body: some View {
        NavigationStack {
            VStack {
                CameraPreview(session: $session.session)
                    .frame(height: 400)
                VStack {
                    HStack {
                        Picker(
                            String(localized: .CaptureSequence.camera),
                            selection: $session.selectedCamera
                        ) {
                            Text(.CaptureSequence.back).tag(AVCaptureDevice.Position.back)
                            Text(.CaptureSequence.front).tag(AVCaptureDevice.Position.front)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: session.selectedCamera) { _, newCamera in
                            session.updateCamera(to: newCamera)
                        }
                    }
                    HStack {
                        VStack {
                            Slider(
                                value: $session.interval,
                                in: session.unit.range,
                                step: session.unit.step
                            )
                            Text(
                                .CaptureSequence.interval(
                                    Int(session.interval),
                                    session.unit.formatted
                                )
                            )
                        }
                        Picker("", selection: $session.unit) {
                            ForEach(TimeUnit.allCases) { u in
                                Text(u.rawValue).tag(u)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: session.unit) { _, newUnit in
                            session.interval = newUnit.range.lowerBound
                        }
                    }
                }
                .padding(.horizontal)
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
                
                if session.isRecording {
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
                if session.nextCaptureCountdown <= 0, session.isRecording {
                    session.takePhoto()
                }
            }
            .idleTimerDisabled(session.isRecording)
            .onDisappear {
                PhoneConnectivityManager.shared.sendReset()
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
