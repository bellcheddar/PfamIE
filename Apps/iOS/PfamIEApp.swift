import PfamIEKit
import SwiftUI

/// iPhone and iPad. One target: the root view adapts to the size class, so the
/// iPad gets a three-column split and the iPhone gets five tabs from the same
/// code.
@main
struct PfamIEApp: App {
    @State private var app = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            if let assets = BundledAssets.assets() {
                RootView(assets: assets)
                    .environment(app)
            } else {
                MissingAssetsView()
            }
        }
        .commands {
            // iPad hardware keyboards get the same shortcuts as the Mac.
            CommandGroup(after: .toolbar) {
                Button("Galaxy") { }.keyboardShortcut("1", modifiers: .command)
                Button("Oracle") { }.keyboardShortcut("2", modifiers: .command)
            }
        }
    }
}

/// Shown when the app was built without running the forge, which is a build
/// mistake and should say so rather than looking like a data-loading failure.
struct MissingAssetsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Pfam data in this build", systemImage: "shippingbox")
        } description: {
            Text("Run forge/build_assets.py, then rebuild. The app bundle has no manifest.json.")
        }
    }
}
