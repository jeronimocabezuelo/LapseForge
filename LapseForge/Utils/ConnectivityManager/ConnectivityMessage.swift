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
    case dataReceived
    
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
        case .dataReceived:
            return ["type": "dataReceived"]
        }
    }
    
    var data: Data? {
        guard let dictionary else { return nil }
        
        return try? JSONSerialization.data(withJSONObject: dictionary)
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
        case "dataReceived":
            self = .dataReceived
        default: return nil
        }
    }
    
    init?(data: Data) {
        guard let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        
        self.init(dictionary: dictionary)
    }
}
