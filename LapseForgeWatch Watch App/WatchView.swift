//
//  WatchView.swift
//  LapseForgeWatch Watch App
//
//  Created by Jerónimo Cabezuelo Ruiz on 12/10/25.
//

import SwiftUI
import Combine

class WatchViewModel: ObservableObject {
    @Published var state: RecordingState?
    @Published var image: UIImage?
    
    private var cancellables = Set<AnyCancellable>()
    
    init(manager: WatchConnectivityManager = .shared) {
        // Publicación directa del snapshot tipado
        manager.$lastReceivedMessage
            .compactMap({ $0 })
            .sink { [weak self] message in
                guard let self else { return }
                setState(from: message)
            }
            .store(in: &cancellables)
        
        manager.$lastReceivedData
            .compactMap({ $0 })
            .sink { [weak self] data in
                guard let self else { return }
                setImage(data: data)
            }
            .store(in: &cancellables)
        
        manager.receivedMessageSubject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                guard let self else { return }
                setState(from: message)
            }
            .store(in: &cancellables)
        
        // Si quieres fallback inicial (por ejemplo, si ya hay applicationContext al activar):
        // también puedes leer manager.lastState en init y propagarlo:
        if let initial = manager.lastReceivedMessage {
            setState(from: initial)
        }
    }
    
    private func setState(from message: ConnectivityMessage) {
        switch message {
        case .state(let state):
            self.state = state
        case .reset:
            self.image = nil
            self.state = nil
        default: break
        }
    }
    
    private func setImage(data: Data) {
        if let image = UIImage(data: data) {
            self.image = image
        }
    }
    
    // Acción de UI: reenviar evento al iPhone
    func buttonTapped() {
        guard let currentIsRecording = self.state?.isRecording else { return }
        WatchConnectivityManager.shared.send(
            message: .isRecording(!currentIsRecording),
            reply: { reply in
                print("Reply:", reply)
            },
            failure: { error in
                print("WC error:", error.localizedDescription)
            }
        )
    }
}

struct WatchView: View {
    @ObservedObject var viewModel = WatchViewModel()

    var body: some View {
        VStack(spacing: 8) {
            if let state = viewModel.state {
                if let image = viewModel.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
                HStack {
                    Button(action: {
                        viewModel.buttonTapped()
                    }, label: {
                        Image(systemName: state.isRecording ? "pause.fill" : "play.fill")
                            .font(.body)
                            .foregroundColor(.white)
                            .padding(10)
                            .squareByIntrinsic()
                            .glassEffect(.regular.tint(state.isRecording ? .red : .green).interactive())
                    })
                    .buttonStyle(.plain)
                    
                    VStack {
                        Text(.CaptureSequence.captures(state.capturesCount))
                        Text(.CaptureSequence.elapsedTimeShort(formatElapsedTime(state.duration)))
                            .lineLimit(nil)
                    }
                }
                if state.isRecording {
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
        vm.state = RecordingState(
            isRecording: true,
            capturesCount: 100,
            duration: 23.633333
        )
        vm.image = UIImage(named: "mock")
        return vm
    }
}

#Preview {
    WatchView(viewModel: .mock)
}
