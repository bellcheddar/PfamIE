import SwiftUI

#if canImport(WebKit)
import WebKit

/// The interactive structure viewer: a bundled Mol* build in a WKWebView.
///
/// Mol* ships as one 5 MB script, so the viewer works with no network beyond
/// fetching the model itself, and a cached model means the whole thing works
/// offline. WebKit is absent on watchOS, which is why this whole file is
/// conditional and `StructurePeek` falls back to a cached image there.
struct MolViewer: PlatformViewRepresentable {

    let structureURL: URL
    let highlight: ClosedRange<Int>?
    let accent: Color
    let background: Color

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedStructure: URL?
    }

    func makePlatformView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = false
        // Mol* draws with WebGL and needs no inline media gestures.
        #if os(iOS) || os(visionOS)
        configuration.allowsInlineMediaPlayback = true
        #endif

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        #if os(macOS)
        // `isOpaque` is read-only on AppKit's WKWebView; this is the supported
        // way to let the page's own background through.
        webView.setValue(false, forKey: "drawsBackground")
        #else
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        #endif
        return webView
    }

    func updatePlatformView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedStructure != structureURL else { return }
        context.coordinator.loadedStructure = structureURL

        guard let assets = MolstarAssets.directory else {
            webView.loadHTMLString(MolstarAssets.missingAssetsPage, baseURL: nil)
            return
        }

        let html = MolstarAssets.page(
            structureFileName: structureURL.lastPathComponent,
            highlight: highlight,
            accent: accent.hexString,
            background: background.hexString
        )

        // Serve from a directory that contains both molstar.js and the model,
        // so no request ever leaves the app and the CSP stays trivial.
        let staging = MolstarAssets.staging(structure: structureURL, assets: assets)
        let pageURL = staging.appendingPathComponent("viewer.html")
        try? html.write(to: pageURL, atomically: true, encoding: .utf8)
        webView.loadFileURL(pageURL, allowingReadAccessTo: staging)
    }
}

/// Where the bundled Mol* build lives, and the page that drives it.
enum MolstarAssets {

    /// The `molstar` folder copied in from `assets/bundle`.
    static var directory: URL? {
        for bundle in [Bundle.main] + Bundle.allBundles {
            if let url = bundle.url(forResource: "molstar", withExtension: nil),
               FileManager.default.fileExists(
                   atPath: url.appendingPathComponent("molstar.js").path
               ) {
                return url
            }
        }
        return nil
    }

    /// A scratch folder holding the viewer page, the Mol* build and the model.
    static func staging(structure: URL, assets: URL) -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("PfamIEStructure", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        for name in ["molstar.js", "molstar.css"] {
            let destination = root.appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.copyItem(
                    at: assets.appendingPathComponent(name), to: destination
                )
            }
        }
        let model = root.appendingPathComponent(structure.lastPathComponent)
        if !FileManager.default.fileExists(atPath: model.path) {
            try? FileManager.default.copyItem(at: structure, to: model)
        }
        return root
    }

    static let missingAssetsPage = """
        <html><body style="font:14px -apple-system;padding:24px;color:#8A96AD">
        The structure viewer is not bundled in this build.
        </body></html>
        """

    /// The viewer page.
    ///
    /// Domain highlighting uses UniProt residue numbers straight from Pfam,
    /// which is exactly what an AlphaFold model is numbered in. The rest of the
    /// chain is left translucent so the domain reads as part of a whole protein
    /// rather than floating on its own.
    static func page(
        structureFileName: String,
        highlight: ClosedRange<Int>?,
        accent: String,
        background: String
    ) -> String {
        let selection = highlight.map {
            "{ start_auth_seq_id: \($0.lowerBound), end_auth_seq_id: \($0.upperBound) }"
        } ?? "null"

        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <link rel="stylesheet" href="molstar.css">
        <style>
          html, body { margin:0; padding:0; height:100%; background:\(background); }
          #app { position:absolute; inset:0; }
          .msp-plugin .msp-layout-expanded { background:\(background); }
        </style>
        </head>
        <body>
        <div id="app"></div>
        <script src="molstar.js"></script>
        <script>
        const HIGHLIGHT = \(selection);
        const ACCENT = '\(accent)';

        molstar.Viewer.create('app', {
            layoutIsExpanded: false,
            layoutShowControls: false,
            layoutShowSequence: false,
            layoutShowLog: false,
            layoutShowLeftPanel: false,
            viewportShowExpand: false,
            viewportShowSelectionMode: false,
            viewportShowAnimation: false,
            pdbProvider: 'rcsb',
            emdbProvider: 'rcsb'
        }).then(async viewer => {
            window.__viewer = viewer;
            await viewer.loadStructureFromUrl('\(structureFileName)', 'mmcif', false);
            if (HIGHLIGHT) { applyHighlight(); }
            window.webkit && window.webkit.messageHandlers &&
                window.webkit.messageHandlers.ready &&
                window.webkit.messageHandlers.ready.postMessage('ready');
        });

        // Colour the Pfam domain against a translucent remainder. AlphaFold
        // models are numbered in UniProt coordinates, so the Pfam range needs
        // no mapping: auth_seq_id is the residue number Pfam quotes.
        function applyHighlight() {
            const plugin = window.__viewer.plugin;
            const data = plugin.managers.structure.hierarchy.current.structures[0];
            if (!data) return;
            plugin.managers.structure.component.updateRepresentationsTheme(
                data.components, { color: 'uniform', colorParams: { value: 0x8A96AD } }
            );
            const Q = molstar.MolScriptBuilder;
            const expression = Q.struct.generator.atomGroups({
                'residue-test': Q.core.rel.inRange([
                    Q.struct.atomProperty.macromolecular.auth_seq_id(),
                    HIGHLIGHT.start_auth_seq_id, HIGHLIGHT.end_auth_seq_id
                ])
            });
            plugin.managers.structure.selection.fromExpression('set', expression);
        }

        function setPlddtColouring(on) {
            const plugin = window.__viewer.plugin;
            const data = plugin.managers.structure.hierarchy.current.structures[0];
            if (!data) return;
            plugin.managers.structure.component.updateRepresentationsTheme(
                data.components,
                on ? { color: 'plddt-confidence' }
                   : { color: 'uniform', colorParams: { value: 0x8A96AD } }
            );
            if (!on && HIGHLIGHT) applyHighlight();
        }
        </script>
        </body>
        </html>
        """
    }
}

extension Color {
    /// "#RRGGBB" for handing a SwiftUI colour to the web view.
    var hexString: String {
        #if canImport(UIKit)
        let resolved = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        resolved.getRed(&r, green: &g, blue: &b, alpha: &a)
        #elseif canImport(AppKit)
        let resolved = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = resolved.redComponent, g = resolved.greenComponent, b = resolved.blueComponent
        #else
        let r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        #endif
        return String(format: "#%02X%02X%02X",
                      Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

#endif
