import Observation
import SwiftUI

/// Loads the engine and holds the state every tab shares.
///
/// Loading maps ~40 MB and opens a 90 MB database, so it happens off the main
/// thread and the UI shows its progress rather than a frozen launch screen.
@MainActor
@Observable
public final class AppEnvironment {

    public enum LoadState: Sendable {
        case loading
        case ready
        case failed(String)

        public var isReady: Bool { if case .ready = self { return true }; return false }
    }

    public private(set) var state: LoadState = .loading
    public private(set) var engine: PfamIEEngine?

    /// Every family, in row order. Held once: the Galaxy needs all 30,031
    /// points and the alternative is each tab reloading them.
    public private(set) var families: [Family] = []
    public private(set) var clans: [Clan] = []
    public private(set) var clanByAccession: [ClanID: Clan] = [:]
    public private(set) var meta: [String: String] = [:]

    /// The last Oracle result, shared so the Galaxy can drop its comet and the
    /// watch can be told about it.
    public var lastClassification: PfamIEEngine.Classification?

    public var appearance: AppearanceChoice {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: Self.appearanceKey) }
    }

    private static let appearanceKey = "appearance"

    public init() {
        // Dark is the default, not "follow the system". The Galaxy is a
        // starfield: on a white ground the point cloud's additive glow reads
        // as a white blob, and the whole instrument metaphor goes with it.
        // Light mode is fully supported and one tap away in Settings.
        let stored = UserDefaults.standard.string(forKey: Self.appearanceKey)
        self.appearance = AppearanceChoice(rawValue: stored ?? "") ?? .dark
    }

    public func load(assets: PfamIEEngine.Assets) async {
        state = .loading
        do {
            let engine = try await Task.detached(priority: .userInitiated) {
                try PfamIEEngine(assets: assets)
            }.value

            let loaded = try await Task.detached(priority: .userInitiated) {
                (
                    families: try await engine.store.allFamilies(),
                    clans: try await engine.store.allClans(),
                    meta: try await engine.store.meta()
                )
            }.value

            self.engine = engine
            self.families = loaded.families
            self.clans = loaded.clans
            self.clanByAccession = Dictionary(
                uniqueKeysWithValues: loaded.clans.map { ($0.accession, $0) }
            )
            self.meta = loaded.meta
            self.state = .ready
        } catch {
            self.state = .failed(String(describing: error))
        }
    }

    public func family(_ accession: PfamID) -> Family? {
        families.first { $0.accession == accession }
    }

    public func family(row: Int) -> Family? {
        row >= 0 && row < families.count ? families[row] : nil
    }

    public func clanColour(for family: Family, theme: Theme) -> Color {
        guard let clan = family.clan, let record = clanByAccession[clan] else {
            return theme.clanColour(hue: -1)
        }
        return theme.clanColour(hue: record.hue)
    }

    /// What Settings shows about the data behind the app.
    public var provenance: [(String, String)] {
        [
            ("Pfam release", meta["pfam_release"] ?? "unknown"),
            ("Families", families.count.formatted()),
            ("Clans", clans.count.formatted()),
            ("Protein model", meta["protein_model"] ?? "unknown"),
            ("Text model", meta["text_model"] ?? "unknown"),
            // Both figures, labelled. Showing only the seed number would be
            // the single most misleading thing this screen could do.
            ("Top-1 on real proteins", percent(meta["real_top1"])),
            ("Top-5 on real proteins", percent(meta["real_top5"])),
            ("Benchmark size", (meta["real_proteins"] ?? "?") + " UniProt proteins"),
            ("Top-1 on held-out Pfam seeds", percent(meta["heldout_seed_top1"])),
        ]
    }

    private func percent(_ raw: String?) -> String {
        guard let raw, let value = Double(raw) else { return "unknown" }
        return (value * 100).formatted(.number.precision(.fractionLength(1))) + "%"
    }
}
