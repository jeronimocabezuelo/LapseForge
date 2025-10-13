//
//  WatchView.swift
//  LapseForgeWatch Watch App
//
//  Created by Jerónimo Cabezuelo Ruiz on 12/10/25.
//

import SwiftUI
import Combine

class WatchViewModel: ObservableObject {
    @Published var lastState: RecordingState?
    
    private var cancellables = Set<AnyCancellable>()
    
    init(manager: WatchConnectivityManager = .shared) {
        // Publicación directa del snapshot tipado
        manager.$lastState
            .sink { [weak self] state in
                guard let self else { return }
                self.lastState = state
            }
            .store(in: &cancellables)
        
        // Si quieres fallback inicial (por ejemplo, si ya hay applicationContext al activar):
        // también puedes leer manager.lastState en init y propagarlo:
        if let initial = manager.lastState {
            self.lastState = initial
        }
    }
    
    // Acción de UI: reenviar evento al iPhone
    func captureTapped() {
        WatchConnectivityManager.shared.send(message: ["event": "captureTapped"]) { reply in
            print("Reply:", reply)
        } error: { err in
            print("WC error:", err.localizedDescription)
        }
    }
}

struct WatchView: View {
    @ObservedObject var viewModel = WatchViewModel()

    var body: some View {
        VStack(spacing: 8) {
            if let s = viewModel.lastState {
                Button(action: {
                    viewModel.captureTapped()
                }, label: {
                    Image(systemName: s.isRecording ? "pause.fill" : "play.fill")
                        .font(.largeTitle)
                        .foregroundColor(.white)
                        .padding(15)
                        .squareByIntrinsic()
                        .glassEffect(.regular.tint(s.isRecording ? .red : .green).interactive())
                })
                .buttonStyle(.plain)
                
                Text(.CaptureSequence.captures(s.capturesCount))
                Text(.CaptureSequence.elapsedTimeShort(formatElapsedTime(s.duration)))
                    .lineLimit(nil)
                if s.isRecording {
                    Text(.CaptureSequence.recording)
                        .foregroundColor(.red)
                } else {
                    Text(" ")
                    
                }
            } else {
                Text(.CaptureSequence.noState)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(.CaptureSequence.noStateDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func formatElapsedTime(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension WatchViewModel {
    static var mock: WatchViewModel {
        let vm = WatchViewModel()
        vm.lastState = RecordingState(
            isRecording: true,
            capturesCount: 100,
            duration: 23.633333
        )
        return vm
    }
}

#Preview {
    WatchView(viewModel: .mock)
}
