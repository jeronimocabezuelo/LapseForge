//
//  ConnectivityMessage.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 14/10/25.
//

import Foundation

enum ConnectivityMessage {
    case isRecording(Bool)
    case state(RecordingState)
    case reset
    case status(Bool)
    
    var dictionary: [String: Any]? {
        switch self {
        case .isRecording(let isRecording):
            return ["type": "isRecording", "value": isRecording]
        case .state(let state):
            guard let value = try? JSONEncoder().encode(state) else {
                return nil
            }
            return ["type": "state", "value": value]
        case .reset:
            return ["type": "reset"]
        case .status(let status):
            return ["type": "status", "value": status]
        }
    }
}

extension ConnectivityMessage {
    init?(dictionary: [String: Any]) {
        guard let type = dictionary["type"] as? String else {
            return nil
        }
        
        switch type {
        case "isRecording":
            guard let value = dictionary["value"] as? Bool else {
                return nil
            }
            self = .isRecording(value)
        case "state":
            guard let data = dictionary["value"] as? Data else {
                return nil
            }
            guard let value = try? JSONDecoder().decode(RecordingState.self, from: data) else {
                return nil
            }
            self = .state(value)
        case "reset":
            self = .reset
        case "status":
            guard let value = dictionary["value"] as? Bool else {
                return nil
            }
            self = .status(value)
        default: return nil
        }
    }
}
