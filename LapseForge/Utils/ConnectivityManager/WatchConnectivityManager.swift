//
//  WatchConnectivityManager.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 13/10/25.
//


import Foundation
import WatchConnectivity
import Combine

final class WatchConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    
    @Published private(set) var lastReceivedPayload: [String: Any] = [:]
    let lastReceivedPayloadSubject = PassthroughSubject<[String: Any], Never>()
    
    var isReachable: Bool {
        WCSession.default.isReachable
    }
    
    private var activated = false
    private let loggingEnabled = true
    
    private override init() {
        super.init()
    }
    
    func activate() {
        guard WCSession.isSupported() else {
            if loggingEnabled {
                print("[WatchConnectivityManager] WCSession is not supported on this device.")
            }
            return
        }
        guard !activated else {
            if loggingEnabled {
                print("[WatchConnectivityManager] Already activated.")
            }
            return
        }
        
        let session = WCSession.default
        session.delegate = self
        session.activate()
        activated = true
        
        if loggingEnabled {
            print("[WatchConnectivityManager] WCSession activated.")
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if loggingEnabled {
            if let error = error {
                print("[WatchConnectivityManager] Activation completed with error: \(error.localizedDescription)")
            } else {
                print("[WatchConnectivityManager] Activation completed with state: \(activationState.rawValue)")
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        if loggingEnabled {
            print("[WatchConnectivityManager] Did receive message: \(message)")
        }
        DispatchQueue.main.async { [weak self] in
            self?.lastReceivedPayload = message
            self?.lastReceivedPayloadSubject.send(message)
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        if loggingEnabled {
            print("[WatchConnectivityManager] Did receive application context: \(applicationContext)")
        }
        DispatchQueue.main.async { [weak self] in
            self?.lastReceivedPayload = applicationContext
            self?.lastReceivedPayloadSubject.send(applicationContext)
        }
    }
    
    // MARK: - Sending
    
    func send(message: [String: Any], reply: (([String: Any]) -> Void)? = nil, error: ((Error) -> Void)? = nil) {
        guard isReachable else {
            if loggingEnabled {
                print("[WatchConnectivityManager] Cannot send message, phone not reachable.")
            }
            let err = NSError(domain: "WatchConnectivity", code: 1, userInfo: [NSLocalizedDescriptionKey: "Phone not reachable"])
            error?(err)
            return
        }
        
        WCSession.default.sendMessage(message, replyHandler: reply, errorHandler: { sendError in
            if self.loggingEnabled {
                print("[WatchConnectivityManager] Error sending message: \(sendError.localizedDescription)")
            }
            error?(sendError)
        })
        
        if loggingEnabled {
            print("[WatchConnectivityManager] Sent message: \(message)")
        }
    }
    
    func sendApplicationContext(_ context: [String: Any]) throws {
        if loggingEnabled {
            print("[WatchConnectivityManager] Sending application context: \(context)")
        }
        try WCSession.default.updateApplicationContext(context)
    }
    
//    func sessionDidBecomeInactive(_ session: WCSession) { }
//    
//    func sessionDidDeactivate(_ session: WCSession) { }
}
