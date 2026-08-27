import PfamIEKit
import SwiftUI

/// visionOS. The tabs open as flat windows reusing the shared views untouched,
/// and the Galaxy gets a volume of its own: a point cloud you walk around
/// rather than orbit with a finger.
@main
struct PfamIEVisionApp: App {
    @State private var app = AppEnvironment()
    @Environment(\.openWindow) private var openWindowFromScene

    var body: some Scene {
        WindowGroup(id: "main") {
            if let assets = BundledAssets.assets() {
                RootView(assets: assets)
                    .environment(app)
                    .ornament(attachmentAnchor: .scene(.trailing)) {
                        OpenVolumeButton()
                    }
                    #if DEBUG
                    // Lets a screenshot or a UI test reach the volumetric
                    // scene, which otherwise needs a gaze-and-pinch nothing
                    // outside the headset can perform.
                    .task {
                        if UserDefaults.standard.bool(forKey: "PfamIEOpenVolume") {
                            openVolumeOnLaunch()
                        }
                    }
                    #endif
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

/// Opens the Galaxy as a volume beside the window.
///
/// Without this there is no route to the volumetric scene at all: a
/// `WindowGroup` with a volumetric style does not open on its own, and the
/// showpiece of the visionOS build would have shipped unreachable.
struct OpenVolumeButton: View {
    @Environment(\.openWindow) private var openWindow
    @State private var opened = false

    var body: some View {
        Button {
            openWindow(id: "galaxy-volume")
            opened = true
        } label: {
            Label("Open the Galaxy as a volume", systemImage: "cube.transparent")
                .labelStyle(.iconOnly)
                .font(.title2)
                .padding(10)
        }
        .buttonStyle(.borderless)
        .glassBackgroundEffect()
        .help("Open the Pfam universe as a volume you can walk around")
        .accessibilityLabel("Open the Galaxy as a volume")
    }
}

private extension PfamIEVisionApp {
    func openVolumeOnLaunch() {
        openWindowFromScene(id: "galaxy-volume")
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
