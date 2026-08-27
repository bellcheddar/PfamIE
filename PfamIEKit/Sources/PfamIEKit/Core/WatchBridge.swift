import Foundation

#if canImport(WatchConnectivity) && (os(iOS) || os(watchOS))
import WatchConnectivity

/// Sends the last Oracle result to the watch.
///
/// `updateApplicationContext` rather than `sendMessage`: the watch should show
/// the last classification whenever it is raised, not only while the phone is
/// awake and reachable. Only the summary crosses, never the sequence.
@MainActor
public final class WatchBridge: NSObject {

    public static let shared = WatchBridge()

    /// What the watch shows. Kept deliberately small: this goes over the air
    /// on every classification, and the watch has no use for the embedding or
    /// the full hit list.
    public struct Payload: Codable, Sendable {
        public let family: String
        public let accession: String
        public let clan: String?
        public let probability: Double
        public let band: String
        public let residueCount: Int
        public let receivedAt: Date
    }

    private var session: WCSession? {
        guard WCSession.isSupported() else { return nil }
        return WCSession.default
    }

    public func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    public func send(_ classification: PfamIEEngine.Classification, clanName: String?) {
        guard let session, session.activationState == .activated else { return }
        guard let top = classification.hits.first else { return }

        let payload = Payload(
            family: top.family.displayName,
            accession: top.family.accession.rawValue,
            clan: clanName,
            probability: Double(top.probability),
            band: classification.band.rawValue,
            residueCount: classification.residueCount,
            receivedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        // A failed context update is not worth surfacing: the watch is a
        // convenience, and the phone has already shown the result.
        try? session.updateApplicationContext(["result": data])
    }
}

extension WatchBridge: WCSessionDelegate {
    nonisolated public func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {}

    #if os(iOS)
    nonisolated public func sessionDidBecomeInactive(_ session: WCSession) {}
    nonisolated public func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
#endif
