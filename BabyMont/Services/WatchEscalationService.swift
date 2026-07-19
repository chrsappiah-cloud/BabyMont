import Foundation

#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

@MainActor
final class WatchEscalationService: NSObject, WatchEscalationServicing {
    private(set) var state: MonitoringState = .idle

    func configure() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else {
            state = .unavailable("Apple Watch connectivity is not supported.")
            return
        }

        WCSession.default.delegate = self
        WCSession.default.activate()
        state = .active
        #else
        state = .unavailable("WatchConnectivity is not available.")
        #endif
    }

    func escalate(_ candidate: AlertCandidate) async -> Bool {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported(), WCSession.default.isPaired else {
            state = .unavailable("No paired Apple Watch is available.")
            return false
        }

        let payload: [String: Any] = [
            "id": candidate.id.uuidString,
            "title": candidate.title,
            "detail": candidate.detail,
            "severity": candidate.severity.rawValue,
            "timestamp": Date.now.timeIntervalSince1970
        ]

        if WCSession.default.isReachable {
            return await withCheckedContinuation { continuation in
                WCSession.default.sendMessage(payload, replyHandler: { _ in
                    continuation.resume(returning: true)
                }, errorHandler: { [weak self] error in
                    Task { @MainActor in
                        self?.state = .failed(error.localizedDescription)
                    }
                    continuation.resume(returning: false)
                })
            }
        } else {
            do {
                try WCSession.default.updateApplicationContext(payload)
                return true
            } catch {
                state = .failed(error.localizedDescription)
                return false
            }
        }
        #else
        state = .unavailable("WatchConnectivity is not available.")
        return false
        #endif
    }
}

#if canImport(WatchConnectivity)
extension WatchEscalationService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            if let error {
                self.state = .failed(error.localizedDescription)
            } else {
                self.state = activationState == .activated ? .active : .unavailable("Watch session is not activated.")
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
#endif
