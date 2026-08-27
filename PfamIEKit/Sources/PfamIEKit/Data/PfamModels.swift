import Foundation

/// A Pfam accession. A distinct type because the app passes these through
/// navigation, deep links and context menus constantly, and `String` there
/// invites confusion with an identifier like "Pkinase".
public struct PfamID: Hashable, Sendable, Codable, CustomStringConvertible, Comparable, Identifiable {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
    /// Its own identity, so it can drive a `.sheet(item:)` directly.
    public var id: String { rawValue }
    public static func < (a: PfamID, b: PfamID) -> Bool { a.rawValue < b.rawValue }
}

public struct ClanID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public var description: String { rawValue }
    /// Its own identity, so it can drive a `.sheet(item:)` directly.
    public var id: String { rawValue }
}

public enum EntryType: String, Sendable, Codable, CaseIterable {
    case family = "Family"
    case domain = "Domain"
    case repeatUnit = "Repeat"
    case motif = "Motif"
    case coiledCoil = "Coiled-coil"
    case disordered = "Disordered"

    public init(pfamValue: String?) {
        self = EntryType(rawValue: pfamValue ?? "") ?? .family
    }
}

/// The representative UniProt region used for the structure layer.
///
/// AlphaFold models use UniProt numbering, so these coordinates address the
/// predicted structure directly with no residue-mapping step.
public struct Representative: Sendable, Hashable, Codable {
    public let uniprot: String
    public let start: Int
    public let end: Int
    public let length: Int

    public var range: ClosedRange<Int> { start...max(start, end) }
}

public struct Family: Sendable, Hashable, Identifiable, Codable {
    /// Row index into centroids.bin, umap3d.bin and desc_emb.bin.
    public let row: Int
    public let accession: PfamID
    public let version: String
    public let identifier: String
    public let summary: String
    public let abstract: String
    public let type: EntryType
    public let clan: ClanID?
    public let isDUF: Bool
    public let seedCount: Int
    public let proteinCount: Int
    public let taxonCount: Int
    public let structureCount: Int
    public let architectureCount: Int
    public let representative: Representative?
    public let position: SIMD3<Float>

    public var id: PfamID { accession }

    /// What a chip shows: "Pkinase" reads better than "PF00069" in running text,
    /// but the accession is what people search for.
    public var displayName: String { identifier }
}

public struct Clan: Sendable, Hashable, Identifiable, Codable {
    public let accession: ClanID
    public let identifier: String?
    public let summary: String?
    /// Stable hue in [0, 1), assigned in the forge so Galaxy colours never
    /// shuffle between builds.
    public let hue: Double
    public let familyCount: Int

    public var id: ClanID { accession }
}

/// One distinct N-to-C domain architecture, shared by every family in it.
public struct Architecture: Sendable, Hashable, Identifiable, Codable {
    public let id: Int
    public let members: [PfamID]
    public let proteinCount: Int
    public let representativeUniProt: String?
    public let representativeLength: Int?

    /// "PF00018-PF00017-PF07714", N-terminal first.
    ///
    /// Derived rather than stored: as a column it cost 16 MB of the shipped
    /// database to repeat what `members` already says.
    public var signature: String {
        members.map(\.rawValue).joined(separator: "-")
    }
}

/// How often two families travel together, and in which order.
public struct CooccurrenceEdge: Sendable, Hashable {
    public let familyRow: Int
    public let partnerRow: Int
    public let proteinCount: Int
    /// Proteins where the partner sits N-terminal to the family.
    public let countBefore: Int
    /// Proteins where the partner sits C-terminal to it.
    public let countAfter: Int

    /// Fraction of shared proteins where the partner comes first, or nil when
    /// the pair is too rare to phrase an ordering claim about.
    public var fractionBefore: Double? {
        let total = countBefore + countAfter
        guard total >= 10 else { return nil }
        return Double(countBefore) / Double(total)
    }

    /// How to say the ordering out loud.
    ///
    /// Domain order is strongly conserved: measured across 71,573 pairs
    /// sharing at least ten proteins, 97.7% are invariant, one way or the
    /// other. Rendering those as "100%" put the same number on almost every
    /// row, which is uninformative and reads like a bug. The invariant case
    /// gets words, and a percentage is kept for the 2.3% that actually vary,
    /// which are the interesting ones.
    public enum Ordering: Sendable, Equatable {
        case alwaysBefore
        case alwaysAfter
        case mostlyBefore(Double)
        case mostlyAfter(Double)
        case tooFewToSay
    }

    public var ordering: Ordering {
        guard let fraction = fractionBefore else { return .tooFewToSay }
        if fraction >= 0.98 { return .alwaysBefore }
        if fraction <= 0.02 { return .alwaysAfter }
        return fraction >= 0.5 ? .mostlyBefore(fraction) : .mostlyAfter(1 - fraction)
    }
}
