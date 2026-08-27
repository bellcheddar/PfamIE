import Foundation

/// Everywhere the app can go from anywhere else.
///
/// Every family chip in every tab offers the same actions, and they all resolve
/// to one of these. Keeping the set closed is what stops each tab growing its
/// own private navigation and leaving the others as dead ends.
public enum Destination: Hashable, Sendable {
    /// The universal family card, presented as a sheet over whatever is showing.
    case family(PfamID)
    /// Fly the Galaxy camera to a family, or just show the map.
    case galaxy(focus: PfamID?)
    /// Open the Oracle, optionally pre-filled with a sequence to classify.
    case oracle(prefill: String?)
    /// Show what else is built like this run of domains.
    case grammarian(architecture: [PfamID])
    /// Open a domain of unknown function with its nearest annotated neighbours.
    case prospector(duf: PfamID)
    /// The structure viewer, with an optional region to highlight.
    case structure(uniprot: String, highlight: ClosedRange<Int>?)
    /// The Field Guide, optionally with a query already typed.
    case fieldGuide(query: String?)
}

/// The five tabs, in order.
public enum AppTab: Int, CaseIterable, Hashable, Sendable, Identifiable {
    case galaxy, oracle, grammarian, prospector, fieldGuide

    public var id: Int { rawValue }

    public var title: String {
        switch self {
        case .galaxy: return "Galaxy"
        case .oracle: return "Oracle"
        case .grammarian: return "Grammarian"
        case .prospector: return "Prospector"
        case .fieldGuide: return "Field Guide"
        }
    }

    public var symbol: String {
        switch self {
        case .galaxy: return "sparkles"
        case .oracle: return "wand.and.stars"
        case .grammarian: return "puzzlepiece.extension"
        case .prospector: return "questionmark.diamond"
        case .fieldGuide: return "books.vertical"
        }
    }

    /// One line on what the tab is for, used in empty states and the Mac's
    /// sidebar help.
    public var strapline: String {
        switch self {
        case .galaxy: return "Every Pfam family, mapped"
        case .oracle: return "Classify a sequence"
        case .grammarian: return "How domains are put together"
        case .prospector: return "Leads on the dark proteome"
        case .fieldGuide: return "The offline Pfam atlas"
        }
    }
}
