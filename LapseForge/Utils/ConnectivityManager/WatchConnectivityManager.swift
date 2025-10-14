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
    
    private override init() {
        super.init()
    }
    
    var isReachable: Bool {
        WCSession.default.isReachable
    }
    
    @Published private(set) var lastReceivedMessage: ConnectivityMessage? = nil
    let receivedMessageSubject = PassthroughSubject<ConnectivityMessage, Never>()
    
    private var activated = false
    
    func activate() {
        guard WCSession.isSupported() else {
            if loggingEnabled {
                print("[\(Self.self)] WCSession is not supported on this device.")
            }
            return
        }
        guard !activated else {
            if loggingEnabled {
                print("[\(Self.self)] Already activated.")
            }
            return
        }
        
        let session = WCSession.default
        session.delegate = self
        session.activate()
        activated = true
        
        if loggingEnabled {
            print("[\(Self.self)] WCSession activated.")
        }
    }
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        if loggingEnabled {
            if let error = error {
                print("[\(Self.self)] Activation completed with error: \(error.localizedDescription)")
            } else {
                print("[\(Self.self)] Activation completed with state: \(activationState)")
            }
        }
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        if loggingEnabled {
            print("[\(Self.self)] sessionDidBecomeInactive")
        }
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        if loggingEnabled {
            print("[\(Self.self)] sessionDidDeactivate - reactivating session")
        }
        WCSession.default.activate()
    }
    #endif
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        if loggingEnabled {
            print("[\(Self.self)] reachability changed: \(session.isReachable)")
        }
    }
    
    // MARK: - Sending Messages
    func send(
        message: ConnectivityMessage,
        reply: ((ConnectivityMessage) -> Void)? = nil,
        failure: ((Error) -> Void)? = nil
    ) {
        guard let dictionary = message.dictionary else {
            failure?(NSError(domain: "Failed to serialize message to dictionary", code: -1))
            return
        }
        
        if isReachable {
            send(
                message: dictionary,
                reply: { replyMessage in
                    guard let replyMessage = ConnectivityMessage(dictionary: replyMessage) else {
                        failure?(NSError(domain: "Failed to serialize message to dictionary", code: -1))
                        return
                    }
                    
                    reply?(replyMessage)
                },
                failure: failure
            )
        } else {
            do {
                try sendApplicationContext(dictionary)
            } catch let error {
                failure?(error)
            }
        }
    }
    
    private func send(
        message: [String: Any],
        reply: (([String: Any]) -> Void)? = nil,
        failure: ((Error) -> Void)? = nil
    ) {
        guard isReachable else {
            if loggingEnabled {
                print("[\(Self.self)] send(message:) failed - watch not reachable")
            }
            let error = NSError(domain: "PhoneConnectivity", code: 1, userInfo: [NSLocalizedDescriptionKey: "Watch not reachable"])
            failure?(error)
            return
        }
        
        WCSession.default.sendMessage(message, replyHandler: reply, errorHandler: { error in
            if loggingEnabled {
                print("[\(Self.self)] send(message:) error: \(error.localizedDescription)")
            }
            failure?(error)
        })
        
        if loggingEnabled {
            print("[\(Self.self)] send(message:) sent message: \(message)")
        }
    }
    
    func sendApplicationContext(_ context: [String: Any]) throws {
        do {
            try WCSession.default.updateApplicationContext(context)
            if loggingEnabled {
                print("[\(Self.self)] sendApplicationContext: updated context: \(context)")
            }
        } catch {
            if loggingEnabled {
                print("[\(Self.self)] sendApplicationContext: failed with error: \(error.localizedDescription)")
            }
            throw error
        }
    }
    
    // MARK: - Receiving Messages
    func didReceiveMessage(
        message: ConnectivityMessage,
        replyHandler: ((ConnectivityMessage) -> Void)? = nil
    ) {
        DispatchQueue.main.async {
            self.lastReceivedMessage = message
            self.receivedMessageSubject.send(message)
        }
        
        replyHandler?(.status(true))
    }
    
    func didReceiveMessage(
        message: [String: Any],
        replyHandler: (([String: Any]) -> Void)? = nil
    ) {
        if loggingEnabled {
            print("[\(Self.self)] didReceiveMessage: \(message)")
        }
        
        guard let message = ConnectivityMessage(dictionary: message) else {
            return
        }
        
        let replyHandler: ((ConnectivityMessage) -> Void)? = replyHandler == nil ? nil : { reply in
            if let replyMessage = reply.dictionary {
                replyHandler?(replyMessage)
            } else {
                replyHandler?(ConnectivityMessage.status(false).dictionary ?? [:])
            }
        }
        
        self.didReceiveMessage(message: message, replyHandler: replyHandler)
    }
    
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        didReceiveMessage(message: message)
    }
    
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        didReceiveMessage(message: message, replyHandler: replyHandler)
    }
    
    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        didReceiveMessage(message: applicationContext)
    }
    
    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        didReceiveMessage(message: userInfo)
    }
}
