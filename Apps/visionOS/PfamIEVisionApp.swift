import PfamIEKit
import SwiftUI

/// visionOS. The tabs open as flat windows reusing the shared views untouched,
/// and the Galaxy gets a volume of its own: a point cloud you walk around
/// rather than orbit with a finger.
@main
struct PfamIEVisionApp: App {
    @State private var app = AppEnvironment()

    var body: some Scene {
        WindowGroup(id: "main") {
            if let assets = BundledAssets.assets() {
                RootView(assets: assets)
                    .environment(app)
            } else {
                MissingAssetsView()
            }
        }
        .defaultSize(width: 1180, height: 800)

        WindowGroup(id: "galaxy-volume") {
            VolumetricGalaxy()
                .environment(app)
        }
        .windowStyle(.volumetric)
        .defaultSize(width: 1.2, height: 1.2, depth: 1.2, in: .meters)
    }
}

struct MissingAssetsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No Pfam data in this build", systemImage: "shippingbox")
        } description: {
            Text("Run forge/build_assets.py, then rebuild.")
        }
    }
}
