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

        // Mixed immersion, not full: this is an instrument, and seeing the
        // desk and the people around you is part of using one.
        ImmersiveSpace(id: "galaxy-immersive") {
            ImmersiveGalaxy()
                .environment(app)
        }
        .immersionStyle(selection: .constant(.mixed), in: .mixed)
    }
}

/// Opens the Galaxy as a volume beside the window.
///
/// Without this there is no route to the volumetric scene at all: a
/// `WindowGroup` with a volumetric style does not open on its own, and the
/// showpiece of the visionOS build would have shipped unreachable.
struct OpenVolumeButton: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openImmersiveSpace) private var openImmersive
    @Environment(\.dismissImmersiveSpace) private var dismissImmersive
    @State private var immersed = false

    var body: some View {
        VStack(spacing: 10) {
            Button {
                openWindow(id: "galaxy-volume")
            } label: {
                Label("Open the Galaxy as a volume", systemImage: "cube.transparent")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .padding(10)
            }
            .help("Open the Pfam universe as a volume you can walk around")
            .accessibilityLabel("Open the Galaxy as a volume")

            Button {
                Task {
                    if immersed {
                        await dismissImmersive()
                        immersed = false
                    } else {
                        immersed = await openImmersive(id: "galaxy-immersive") == .opened
                    }
                }
            } label: {
                Label(immersed ? "Leave the Galaxy" : "Step into the Galaxy",
                      systemImage: immersed ? "arrow.down.right.and.arrow.up.left" : "sparkles")
                    .labelStyle(.iconOnly)
                    .font(.title2)
                    .padding(10)
            }
            .help("Put the Pfam universe around you at room scale")
            .accessibilityLabel(immersed ? "Leave the immersive Galaxy"
                                         : "Step into the immersive Galaxy")
        }
        .buttonStyle(.borderless)
        .glassBackgroundEffect()
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
