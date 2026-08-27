import Observation
import SwiftUI

/// The one object every view reaches for to go somewhere else.
///
/// Held in the environment, so a family chip six levels deep in the Grammarian
/// can open the Oracle without anything in between knowing that is possible.
@MainActor
@Observable
public final class Router {

    public var selectedTab: AppTab = .galaxy

    /// Per-tab navigation stacks, so switching tabs and coming back returns to
    /// where you were rather than to the root.
    public var paths: [AppTab: NavigationPath] = [:]

    /// The family card, presented over everything as a sheet.
    public var presentedFamily: PfamID?

    /// The structure viewer, presented over everything including the card.
    public var presentedStructure: StructureRequest?

    /// Where the Galaxy camera should fly next. Cleared once the renderer has
    /// taken it, so a second request for the same family flies again.
    public var galaxyFocus: PfamID?

    /// Text handed to the Oracle from elsewhere.
    public var oraclePrefill: String?

    /// The architecture the Grammarian should open on.
    public var grammarianArchitecture: [PfamID] = []

    /// The Field Guide's query, when something else set it.
    public var fieldGuideQuery: String?

    public struct StructureRequest: Hashable, Identifiable, Sendable {
        public let uniprot: String
        public let highlight: ClosedRange<Int>?
        public var id: String {
            "\(uniprot)-\(highlight?.lowerBound ?? 0)-\(highlight?.upperBound ?? 0)"
        }
        public init(uniprot: String, highlight: ClosedRange<Int>?) {
            self.uniprot = uniprot
            self.highlight = highlight
        }
    }

    public init() {}

    #if DEBUG
    /// Debug-only launch arguments, so a screenshot or a UI test can land on a
    /// particular tab with a particular sequence already classified. There is
    /// no other way to drive the app from the outside, and "it builds" is not
    /// evidence that the Oracle draws a result correctly.
    ///
    ///     xcrun simctl launch booted com.mdeller.pfamie \
    ///         -PfamIETab oracle -PfamIESequence KVFGRCELAA...
    public func applyLaunchArguments(_ defaults: UserDefaults = .standard) {
        if let name = defaults.string(forKey: "PfamIETab"),
           let tab = AppTab.allCases.first(where: {
               $0.title.lowercased().replacingOccurrences(of: " ", with: "") == name.lowercased()
           }) {
            selectedTab = tab
        }
        if let sequence = defaults.string(forKey: "PfamIESequence"), !sequence.isEmpty {
            oraclePrefill = sequence
            selectedTab = .oracle
        }
        if let query = defaults.string(forKey: "PfamIEQuery"), !query.isEmpty {
            fieldGuideQuery = query
            selectedTab = .fieldGuide
        }
    }
    #endif

    public func go(_ destination: Destination) {
        switch destination {
        case .family(let id):
            presentedFamily = id

        case .galaxy(let focus):
            galaxyFocus = focus
            selectedTab = .galaxy
            presentedFamily = nil

        case .oracle(let prefill):
            if let prefill { oraclePrefill = prefill }
            selectedTab = .oracle
            presentedFamily = nil

        case .grammarian(let architecture):
            grammarianArchitecture = architecture
            selectedTab = .grammarian
            presentedFamily = nil

        case .prospector(let duf):
            selectedTab = .prospector
            presentedFamily = duf

        case .structure(let uniprot, let highlight):
            presentedStructure = StructureRequest(uniprot: uniprot, highlight: highlight)

        case .fieldGuide(let query):
            fieldGuideQuery = query
            selectedTab = .fieldGuide
            presentedFamily = nil
        }
    }

    public func path(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[tab] ?? NavigationPath() },
            set: { self.paths[tab] = $0 }
        )
    }

    /// Called by the Galaxy once it has started flying, so the request is not
    /// replayed on every redraw.
    public func consumeGalaxyFocus() -> PfamID? {
        defer { galaxyFocus = nil }
        return galaxyFocus
    }

    public func consumeOraclePrefill() -> String? {
        defer { oraclePrefill = nil }
        return oraclePrefill
    }
}
