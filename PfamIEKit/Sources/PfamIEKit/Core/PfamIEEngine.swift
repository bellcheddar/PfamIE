import CoreML
import Foundation

/// Everything the app can ask of the baked assets, behind one object.
///
/// An actor: loading maps ~40 MB and every classification runs a Core ML
/// prediction, neither of which belongs on the main thread, and the Oracle can
/// be scanning while the Field Guide searches.
public actor PfamIEEngine {

    public struct Assets: Sendable {
        public let manifest: URL
        public let database: URL
        public let centroids: URL
        public let coordinates: URL
        public let descriptionEmbeddings: URL
        public let proteinModel: URL
        public let textModel: URL
        public let textVocabulary: URL

        /// The standard layout: everything beside `manifest.json` in one folder.
        public init(directory: URL) {
            manifest = directory.appendingPathComponent("manifest.json")
            database = directory.appendingPathComponent("pfam.sqlite")
            centroids = directory.appendingPathComponent("centroids.bin")
            coordinates = directory.appendingPathComponent("umap3d.bin")
            descriptionEmbeddings = directory.appendingPathComponent("desc_emb.bin")
            proteinModel = directory.appendingPathComponent("PfamIEProteinEmbedder.mlmodelc")
            textModel = directory.appendingPathComponent("PfamIETextEmbedder.mlmodelc")
            textVocabulary = directory.appendingPathComponent("minilm_vocab.txt")
        }

        public init(
            manifest: URL, database: URL, centroids: URL, coordinates: URL,
            descriptionEmbeddings: URL, proteinModel: URL, textModel: URL,
            textVocabulary: URL
        ) {
            self.manifest = manifest
            self.database = database
            self.centroids = centroids
            self.coordinates = coordinates
            self.descriptionEmbeddings = descriptionEmbeddings
            self.proteinModel = proteinModel
            self.textModel = textModel
            self.textVocabulary = textVocabulary
        }
    }

    public let manifest: AssetManifest
    public let store: PfamStore
    public let index: CentroidIndex
    public nonisolated let calibration: Calibration

    private let embedder: ProteinEmbedder
    private let semantic: SemanticSearch?
    private let scanner = DomainScanner()

    public init(assets: Assets) throws {
        let manifest = try AssetManifest.load(from: assets.manifest)
        self.manifest = manifest
        self.calibration = manifest.calibrationSettings
        self.store = try PfamStore(url: assets.database)

        let centroidMatrix = try Float16Matrix(
            contentsOf: assets.centroids,
            rows: manifest.families,
            columns: manifest.protein_dim
        )
        self.index = CentroidIndex(matrix: centroidMatrix, calibration: manifest.calibrationSettings)
        self.embedder = try ProteinEmbedder(
            modelURL: assets.proteinModel,
            dimensions: manifest.protein_dim
        )

        // The Field Guide's semantic search is the one part that may be absent:
        // watchOS ships neither the text model nor a 23 MB embedding matrix.
        // Everything else is required, so it throws.
        if FileManager.default.fileExists(atPath: assets.textModel.path),
           FileManager.default.fileExists(atPath: assets.descriptionEmbeddings.path) {
            let descriptionMatrix = try Float16Matrix(
                contentsOf: assets.descriptionEmbeddings,
                rows: manifest.families,
                columns: manifest.text_dim
            )
            self.semantic = try SemanticSearch(
                modelURL: assets.textModel,
                vocabularyURL: assets.textVocabulary,
                matrix: descriptionMatrix
            )
        } else {
            self.semantic = nil
        }
    }

    public nonisolated var supportsSemanticSearch: Bool { true }

    // MARK: - Classification

    public struct Classification: Sendable {
        public let sequence: String
        public let residueCount: Int
        public let truncated: Bool
        /// Ranked families for the headline answer, from whichever window read
        /// the sequence most confidently.
        public let hits: [Hit]
        public let domains: [Domain]
        public let band: Calibration.Band
        /// The residues the headline call came from, or nil when the whole
        /// sequence read more confidently than any window did.
        public let headlineRange: ClosedRange<Int>?
        public let embedding: [Float]
        public let windowsScanned: Int

        public struct Hit: Sendable, Identifiable {
            public let family: Family
            public let similarity: Float
            public let probability: Float
            public var id: PfamID { family.accession }
        }

        public struct Domain: Sendable, Identifiable {
            public let family: Family
            public let start: Int
            public let end: Int
            public let probability: Float
            public let scale: Int
            public var id: String { "\(family.accession)-\(start)" }
            public var length: Int { end - start + 1 }
        }

        /// True when nothing reached the abstain threshold, in which case the
        /// app says so instead of naming the best of a bad set.
        public var isConfident: Bool { band != .none }

        /// True when the sequence was short enough that the architecture track
        /// would only restate the headline call.
        public var singleDomainOnly: Bool { windowsScanned <= 1 }
    }

    public func classify(sequence: String) throws -> Classification {
        let cleaned = ProteinTokenizer.sanitise(sequence)
        let result = try scanner.scan(sequence: cleaned, embedder: embedder, index: index)

        let ranked = Array(result.headline.prefix(10))
        let hitFamilies = try store.families(rows: ranked.map(\.row))
        let byHitRow = Dictionary(uniqueKeysWithValues: hitFamilies.map { ($0.row, $0) })
        let hits = ranked.compactMap { neighbour -> Classification.Hit? in
            guard let family = byHitRow[neighbour.row] else { return nil }
            return Classification.Hit(
                family: family,
                similarity: neighbour.similarity,
                probability: neighbour.probability
            )
        }

        let domainFamilies = try store.families(rows: result.domains.map(\.row))
        let byRow = Dictionary(uniqueKeysWithValues: domainFamilies.map { ($0.row, $0) })
        let domains = result.domains.compactMap { call -> Classification.Domain? in
            guard let family = byRow[call.row] else { return nil }
            return Classification.Domain(
                family: family, start: call.start, end: call.end,
                probability: call.bestProbability, scale: call.scale
            )
        }

        return Classification(
            sequence: cleaned,
            residueCount: result.residueCount,
            truncated: cleaned.utf8.count > ProteinTokenizer.maxResidues,
            hits: hits,
            domains: domains,
            band: calibration.band(for: result.headline.first?.probability ?? 0),
            headlineRange: result.headlineRange,
            embedding: try embedder.embed(
                residues: String(cleaned.prefix(ProteinTokenizer.maxResidues))
            ),
            windowsScanned: result.windowsScanned
        )
    }

    // MARK: - Search

    public struct SearchResult: Sendable, Identifiable {
        public let family: Family
        public let score: Float
        public let literal: Bool
        public var id: PfamID { family.accession }
    }

    /// Literal and semantic search, merged.
    ///
    /// Literal hits lead, because someone typing "PF00069" or "Peptidase_S8"
    /// wants that exact thing and would be baffled to see it ranked below a
    /// description that merely reads similarly.
    public func search(_ query: String, limit: Int = 40) throws -> [SearchResult] {
        let literal = try store.search(text: query, limit: limit)
        var seen = Set(literal.map(\.row))
        var results = literal.map { SearchResult(family: $0, score: 1, literal: true) }

        if let semantic {
            let hits = try semantic.search(query, limit: limit)
            let rows = hits.map(\.row).filter { !seen.contains($0) }
            let families = try store.families(rows: rows)
            let byRow = Dictionary(uniqueKeysWithValues: families.map { ($0.row, $0) })
            for hit in hits where !seen.contains(hit.row) {
                guard let family = byRow[hit.row] else { continue }
                seen.insert(hit.row)
                results.append(SearchResult(family: family, score: hit.score, literal: false))
            }
        }
        return Array(results.prefix(limit))
    }

    // MARK: - Prospector

    public struct Hypothesis: Sendable, Identifiable {
        public let neighbour: Family
        public let similarity: Float
        public var id: PfamID { neighbour.accession }
    }

    /// The annotated families nearest a domain of unknown function.
    ///
    /// Deliberately excludes other DUFs: "this DUF resembles that DUF" is true
    /// and useless. What the Prospector is for is borrowing a hypothesis from
    /// something that has one.
    public func hypotheses(for family: Family, limit: Int = 10) throws -> [Hypothesis] {
        let neighbours = index.neighbours(ofRow: family.row, k: limit * 6)
        let families = try store.families(rows: neighbours.map(\.row))
        let byRow = Dictionary(uniqueKeysWithValues: families.map { ($0.row, $0) })
        return neighbours.compactMap { neighbour -> Hypothesis? in
            guard let candidate = byRow[neighbour.row], !candidate.isDUF else { return nil }
            return Hypothesis(neighbour: candidate, similarity: neighbour.similarity)
        }
        .prefix(limit)
        .map { $0 }
    }
}
