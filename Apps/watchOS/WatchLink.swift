import Foundation
import Observation
import WatchConnectivity

/// The last Oracle result, as sent from the phone.
struct WatchResult: Codable, Sendable, Equatable {
    let family: String
    let accession: String
    let clan: String?
    let probability: Double
    let band: String
    let residueCount: Int
    let receivedAt: Date

    static let placeholder = WatchResult(
        family: "Nothing yet", accession: "", clan: nil,
        probability: 0, band: "none", residueCount: 0, receivedAt: .distantPast
    )
}

@MainActor
@Observable
final class WatchLink: NSObject {
    private(set) var latest: WatchResult = .placeholder
    private(set) var isReachable = false

    private static let storageKey = "lastResult"

    override init() {
        super.init()
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(WatchResult.self, from: data) {
            latest = stored
        }
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func store(_ result: WatchResult) {
        latest = result
        if let data = try? JSONEncoder().encode(result) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext context: [String: Any]
    ) {
        // applicationContext rather than a message: the watch should show the
        // last result whenever it is opened, not only while the phone is awake.
        guard let payload = context["result"] as? Data,
              let decoded = try? JSONDecoder().decode(WatchResult.self, from: payload)
        else { return }
        Task { @MainActor in self.store(decoded) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }
}
