import Foundation
import WatchConnectivity

/// Forwards the watch app's commands to the selected IINA and answers with the resulting state.
final class WatchRelay: NSObject, WCSessionDelegate, Sendable {
    static let shared = WatchRelay()

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        let command = (message["command"] as? Data).flatMap { try? JSONDecoder().decode(Command.self, from: $0) }
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            let remote = Remote.shared
            let state = if let command { await remote.perform(command) } else { await remote.connectedPlayer()?.state }
            reply(state.flatMap { try? JSONEncoder().encode($0) }.map { ["state": $0] } ?? [:])
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
