//
//  PhoneConnectivityManager.swift
//  LapseForge
//
//  Created by Jerónimo Cabezuelo Ruiz on 13/10/25.
//

import Foundation
import WatchConnectivity
import Combine

@available(iOS 13.0, *)
final class PhoneConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = PhoneConnectivityManager()

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
                print("[PhoneConnectivityManager] WCSession is not supported on this device")
            }
            return
        }

        guard !activated else {
            if loggingEnabled {
                print("[PhoneConnectivityManager] WCSession already activated")
            }
            return
        }

        let session = WCSession.default
        session.delegate = self
        session.activate()
        activated = true

        if loggingEnabled {
            print("[PhoneConnectivityManager] WCSession activated")
        }
    }

    // MARK: - WCSessionDelegate

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if loggingEnabled {
            if let error = error {
                print("[PhoneConnectivityManager] session activationDidCompleteWith error: \(error.localizedDescription)")
            } else {
                print("[PhoneConnectivityManager] session activationDidCompleteWith state: \(activationState.rawValue)")
            }
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {
        if loggingEnabled {
            print("[PhoneConnectivityManager] sessionDidBecomeInactive")
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        if loggingEnabled {
            print("[PhoneConnectivityManager] sessionDidDeactivate - reactivating session")
        }
        WCSession.default.activate()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        if loggingEnabled {
            print("[PhoneConnectivityManager] reachability changed: \(session.isReachable)")
        }
    }

    // MARK: - Sending Messages

    func send(
        message: [String: Any],
        reply: (([String: Any]) -> Void)? = nil,
        error: ((Error) -> Void)? = nil
    ) {
        guard WCSession.default.isReachable else {
            if loggingEnabled {
                print("[PhoneConnectivityManager] send(message:) failed - watch not reachable")
            }
            let err = NSError(domain: "PhoneConnectivity", code: 1, userInfo: [NSLocalizedDescriptionKey: "Watch not reachable"])
            error?(err)
            return
        }

        WCSession.default.sendMessage(message, replyHandler: reply, errorHandler: { err in
            if self.loggingEnabled {
                print("[PhoneConnectivityManager] send(message:) error: \(err.localizedDescription)")
            }
            error?(err)
        })

        if loggingEnabled {
            print("[PhoneConnectivityManager] send(message:) sent message: \(message)")
        }
    }

    func sendApplicationContext(_ context: [String: Any]) throws {
        do {
            try WCSession.default.updateApplicationContext(context)
            if loggingEnabled {
                print("[PhoneConnectivityManager] sendApplicationContext: updated context: \(context)")
            }
        } catch {
            if loggingEnabled {
                print("[PhoneConnectivityManager] sendApplicationContext: failed with error: \(error.localizedDescription)")
            }
            throw error
        }
    }

    // MARK: - Receiving Messages
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        if loggingEnabled {
            print("[PhoneConnectivityManager] didReceiveMessage: \(message)")
        }
        DispatchQueue.main.async {
            self.lastReceivedPayload = message
            self.lastReceivedPayloadSubject.send(message)
        }
    }

    func session(_ session: WCSession,
                 didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        if loggingEnabled {
            print("[PhoneConnectivityManager] didReceiveMessage with reply: \(message)")
        }
        DispatchQueue.main.async {
            self.lastReceivedPayload = message
            self.lastReceivedPayloadSubject.send(message)
        }
        // Always reply to avoid DeliveryFailed. You can customize the payload as needed.
        replyHandler(["status": "ok"]) 
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        if loggingEnabled {
            print("[PhoneConnectivityManager] didReceiveApplicationContext: \(applicationContext)")
        }
        DispatchQueue.main.async {
            self.lastReceivedPayload = applicationContext
            self.lastReceivedPayloadSubject.send(applicationContext)
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if loggingEnabled {
            print("[PhoneConnectivityManager] didReceiveUserInfo: \(userInfo)")
        }
        DispatchQueue.main.async {
            self.lastReceivedPayload = userInfo
            self.lastReceivedPayloadSubject.send(userInfo)
        }
    }
}
