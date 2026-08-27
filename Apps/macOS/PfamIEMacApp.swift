import PfamIEKit
import SwiftUI
import UniformTypeIdentifiers

/// The Mac app. Native SwiftUI, not Catalyst: the sidebar, the menu bar and
/// dropping a FASTA on the dock icon are all things a Catalyst build does
/// badly or not at all.
@main
struct PfamIEMacApp: App {
    @State private var app = AppEnvironment()
    @State private var droppedSequence: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if let assets = BundledAssets.assets() {
                    RootView(assets: assets)
                        .environment(app)
                        .frame(minWidth: 940, minHeight: 620)
                } else {
                    MissingAssetsView().frame(minWidth: 480, minHeight: 320)
                }
            }
            .onOpenURL { url in openSequence(at: url) }
        }
        // A desk instrument, not a utility panel: the Galaxy needs room and
        // the three-column layout wants width. The old default was whatever
        // the minimum happened to be, which opened at 940 by 672.
        .defaultSize(width: 1440, height: 900)
        .commands { PfamIECommands(app: app) }

        Settings {
            SettingsView()
                .environment(app)
                .frame(width: 460)
        }
    }

    /// A FASTA dropped on the dock icon opens the Oracle with it loaded.
    private func openSequence(at url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        droppedSequence = text
        NotificationCenter.default.post(
            name: .pfamIEOpenSequence, object: nil, userInfo: ["sequence": text]
        )
    }
}

extension Notification.Name {
    static let pfamIEOpenSequence = Notification.Name("PfamIEOpenSequence")
}

struct PfamIECommands: Commands {
    let app: AppEnvironment

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About PfamIE") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [
                    .applicationName: "PfamIE",
                    .credits: NSAttributedString(
                        string: "Protein family inference on device.\n"
                            + "Marc C. Deller, D.Phil. \u{00B7} marcdeller.com",
                        attributes: [.font: NSFont.systemFont(ofSize: 11)]
                    ),
                ])
            }
        }
        CommandMenu("Appearance") {
            Picker("Appearance", selection: Binding(
                get: { app.appearance }, set: { app.appearance = $0 }
            )) {
                ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        }
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

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Picker("Appearance", selection: $app.appearance) {
                ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            Section("Data") {
                ForEach(app.provenance, id: \.0) { label, value in
                    LabeledContent(label, value: value)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
