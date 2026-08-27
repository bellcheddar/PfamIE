import SwiftUI
// The watch companion shares the engine, the models and the theme, but none of
// the phone and desktop UI: it carries no assets and shows one glance view.
// SwiftUI on watchOS also lacks TextEditor, fileImporter, textSelection,
// segmented pickers and keyboard shortcuts, so compiling these views there
// fails on about a dozen counts. Excluding them is the honest description of
// the architecture as well as the fix, and it keeps the watch binary small.
#if !os(watchOS)

/// A small structure preview in a card, which expands to the full viewer.
///
/// Offline behaviour is deliberate: if the model is not cached this shows a
/// quiet note rather than a spinner that never resolves or an error that reads
/// like a bug. Everything else in the app works with no network, and the
/// structure layer is the one part that cannot.
public struct StructurePeek: View {
    @Environment(\.theme) private var theme
    @Environment(Router.self) private var router
    @Environment(StructureCache.self) private var cache

    private let uniprot: String
    private let highlight: ClosedRange<Int>?
    private let caption: String

    @State private var status: Status = .idle

    private enum Status: Equatable {
        case idle, loading, cached(URL), unavailable(String)
    }

    public init(uniprot: String, highlight: ClosedRange<Int>?, caption: String) {
        self.uniprot = uniprot
        self.highlight = highlight
        self.caption = caption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                router.go(.structure(uniprot: uniprot, highlight: highlight))
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(theme.bgRaised)
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(theme.hairline)

                    switch status {
                    case .idle, .loading:
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Fetching \(uniprot) from AlphaFold")
                                .font(.caption).foregroundStyle(theme.inkSecondary)
                        }
                    case .cached:
                        VStack(spacing: 8) {
                            Image(systemName: "cube.transparent.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(theme.accentNova)
                            Text("Open the predicted structure")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(theme.inkPrimary)
                        }
                    case .unavailable(let reason):
                        VStack(spacing: 6) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 22))
                                .foregroundStyle(theme.inkSecondary)
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(theme.inkSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 12)
                        }
                    }
                }
                .frame(height: 128)
            }
            .buttonStyle(.plain)
            .disabled(status == .idle || status == .loading)

            Text(caption)
                .font(.caption2)
                .foregroundStyle(theme.inkSecondary)
        }
        .task(id: uniprot) { await prepare() }
    }

    private func prepare() async {
        if let cached = await cache.client.cachedStructure(for: uniprot) {
            status = .cached(cached)
            return
        }
        status = .loading
        do {
            let url = try await cache.client.structure(for: uniprot)
            status = .cached(url)
        } catch {
            status = .unavailable("Structure needs network. \(uniprot) is not cached yet.")
        }
    }
}

/// The full-screen structure viewer.
public struct StructureSheet: View {
    @Environment(\.theme) private var theme
    @Environment(StructureCache.self) private var cache
    @Environment(\.dismiss) private var dismiss

    private let request: Router.StructureRequest
    @State private var structure: URL?
    @State private var failure: String?
    @State private var plddt = false

    public init(request: Router.StructureRequest) { self.request = request }

    public var body: some View {
        NavigationStack {
            Group {
                if let structure {
                    #if canImport(WebKit) && !os(watchOS)
                    MolViewer(
                        structureURL: structure,
                        highlight: plddt ? nil : request.highlight,
                        accent: theme.accentNova,
                        background: theme.bgDeep
                    )
                    .ignoresSafeArea(edges: .bottom)
                    #else
                    ContentUnavailableView(
                        "Not available here",
                        systemImage: "cube.transparent",
                        description: Text("The interactive viewer needs a web view, which this platform does not provide.")
                    )
                    #endif
                } else if let failure {
                    ContentUnavailableView(
                        "No structure",
                        systemImage: "wifi.slash",
                        description: Text(failure)
                    )
                } else {
                    ProgressView("Fetching \(request.uniprot)")
                }
            }
            .background(theme.bgDeep)
            .navigationTitle(request.uniprot)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Toggle("pLDDT", isOn: $plddt)
                        .toggleStyle(.button)
                        .font(.footnote)
                        .help("Colour by AlphaFold's per-residue confidence instead of by domain")
                }
            }
        }
        .task(id: request.uniprot) {
            do { structure = try await cache.client.structure(for: request.uniprot) }
            catch { failure = String(describing: error) }
        }
    }
}

/// Holds the AlphaFold client so every view shares one cache.
@MainActor
@Observable
public final class StructureCache {
    public let client: AlphaFoldClient
    public init(client: AlphaFoldClient = AlphaFoldClient()) { self.client = client }
}

#endif
