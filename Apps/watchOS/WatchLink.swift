import Foundation
import Observation
import WatchConnectivity
import WidgetKit

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

    /// Shared with the complication extension. `UserDefaults.standard` would
    /// be a different container in the widget, so the complication would show
    /// a placeholder forever.
    private static let suite = "group.com.mdeller.pfamie"

    private var store: UserDefaults {
        UserDefaults(suiteName: Self.suite) ?? .standard
    }

    override init() {
        super.init()
        if let data = UserDefaults(suiteName: Self.suite)?.data(forKey: Self.storageKey),
           let stored = try? JSONDecoder().decode(WatchResult.self, from: data) {
            latest = stored
        }
        #if DEBUG
        // Lets a screenshot show a real result. The watch has nothing to
        // display until a paired phone sends one, and a simulator has no
        // paired phone, so the App Store shot would otherwise be the empty
        // state telling the reviewer to go and use their phone.
        if UserDefaults.standard.bool(forKey: "PfamIEWatchDemo") {
            latest = WatchResult(
                family: "PK_Tyr_Ser-Thr", accession: "PF07714", clan: "PKinase",
                probability: 0.91, band: "high", residueCount: 536,
                receivedAt: Date()
            )
        }
        #endif

        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    fileprivate func store(_ result: WatchResult) {
        latest = result
        if let data = try? JSONEncoder().encode(result) {
            store.set(data, forKey: Self.storageKey)
        }
        // Push the face rather than waiting for the system to ask: a result
        // arriving from the phone is exactly when the complication is stale.
        WidgetCenter.shared.reloadTimelines(ofKind: "PfamIELastClassification")
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
