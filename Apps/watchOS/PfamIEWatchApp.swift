import PfamIEKit
import SwiftUI

/// The watch companion.
///
/// No transformer here and no 170 MB of assets: the phone classifies and sends
/// the result across with WatchConnectivity. What the watch is good at is the
/// glance, so that is all it does.
@main
struct PfamIEWatchApp: App {
    @State private var link = WatchLink()

    var body: some Scene {
        WindowGroup {
            WatchGlanceView()
                .environment(link)
        }
    }
}
