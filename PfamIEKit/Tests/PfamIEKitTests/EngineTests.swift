import CoreML
import Foundation
import Testing
@testable import PfamIEKit

@Suite("Protein tokenizer")
struct ProteinTokenizerTests {

    @Test("The hard-coded vocabulary matches the one the forge exported")
    func vocabularyMatchesForge() throws {
        try #require(Assets.root != nil)
        let url = Assets.coreml!.appendingPathComponent("esm2_vocab.json")
        try #require(FileManager.default.fileExists(atPath: url.path))

        struct Spec: Decodable {
            let tokens: [String]
            let cls_token_id: Int
            let eos_token_id: Int
            let pad_token_id: Int
            let unk_token_id: Int
        }
        let spec = try JSONDecoder().decode(Spec.self, from: Data(contentsOf: url))

        #expect(spec.tokens == ProteinTokenizer.vocabulary)
        #expect(Int32(spec.cls_token_id) == ProteinTokenizer.clsID)
        #expect(Int32(spec.eos_token_id) == ProteinTokenizer.eosID)
        #expect(Int32(spec.pad_token_id) == ProteinTokenizer.padID)
        #expect(Int32(spec.unk_token_id) == ProteinTokenizer.unkID)
    }

    @Test("FASTA headers, whitespace and case are cleaned away")
    func sanitising() {
        let raw = ">sp|P00698|LYSC_CHICK Lysozyme C\nkvfg rcel\n123AAM*KRH\n"
        #expect(ProteinTokenizer.sanitise(raw) == "KVFGRCELAAMKRH")
    }

    @Test("Encoding frames the sequence and pools only residues")
    func encodingLayout() {
        let encoding = ProteinTokenizer().encode("ACDE")
        #expect(encoding.residueCount == 4)
        #expect(encoding.truncated == false)
        #expect(encoding.inputIDs.count == ProteinTokenizer.contextLength)
        #expect(encoding.inputIDs[0] == ProteinTokenizer.clsID)
        #expect(encoding.inputIDs[5] == ProteinTokenizer.eosID)
        #expect(encoding.inputIDs[6] == ProteinTokenizer.padID)

        // The pool mask must cover the four residues and nothing else: it is
        // what the model divides by, so a stray 1 shifts every value.
        #expect(encoding.poolMask.reduce(0, +) == 4)
        #expect(encoding.poolMask[0] == 0)
        #expect(encoding.poolMask[1...4].allSatisfy { $0 == 1 })
        #expect(encoding.poolMask[5] == 0)
        #expect(encoding.attentionMask.reduce(0, +) == 6)
    }

    @Test("Over-long sequences truncate rather than overflow")
    func truncation() {
        let long = String(repeating: "A", count: ProteinTokenizer.contextLength + 200)
        let encoding = ProteinTokenizer().encode(long)
        #expect(encoding.truncated)
        #expect(encoding.residueCount == ProteinTokenizer.maxResidues)
        #expect(encoding.inputIDs.last == ProteinTokenizer.eosID)
    }
}

@Suite("Calibration")
struct CalibrationTests {

    private let calibration = Calibration(
        temperature: 0.035, highThreshold: 0.8, midThreshold: 0.5,
        abstainThreshold: 0.3, heldOutTop1: 0.715, heldOutTop5: 0.810
    )

    @Test("Softmax at a small temperature does not overflow")
    func noOverflow() {
        // exp(0.95 / 0.035) is ~1e11 before the shift and inf a little past it.
        let p = calibration.probabilities(forSimilarities: [0.95, 0.9, 0.5, 0.1, -0.2])
        #expect(p.allSatisfy { $0.isFinite })
        #expect(abs(p.reduce(0, +) - 1.0) < 1e-4)
        #expect(p[0] > p[1])
    }

    @Test("A runaway top hit is high confidence, a tie is not")
    func bands() {
        let clear = calibration.probabilities(forSimilarities: [0.90, 0.55, 0.50])
        #expect(calibration.band(for: clear[0]) == .high)

        let tied = calibration.probabilities(forSimilarities: [0.70, 0.699, 0.698, 0.697])
        #expect(calibration.band(for: tied[0]) == .none)
    }
}

@Suite("Engine against the forged assets", .enabled(if: Assets.isForged))
struct ForgedAssetTests {

    @Test("The manifest and the matrices agree")
    func manifestMatchesMatrices() throws {
        let manifest = try Assets.manifest()
        #expect(manifest.families > 25_000)
        #expect(manifest.protein_dim == 320)

        // Float16Matrix throws on a size mismatch, so constructing it is the check.
        let index = try Assets.centroids()
        #expect(index.count == manifest.families)

        let store = try Assets.store()
        #expect(try store.familyCount() == manifest.families)
    }

    @Test("Stored centroids are unit length")
    func centroidsNormalised() throws {
        let index = try Assets.centroids()
        for row in [0, 1, 17, index.count / 2, index.count - 1] {
            let selfSimilarity = index.similarity(row, row)
            #expect(abs(selfSimilarity - 1.0) < 1e-2, "row \(row) gives \(selfSimilarity)")
        }
    }

    @Test("Pkinase's nearest neighbour is the tyrosine kinase family")
    func kinaseGeometry() throws {
        let store = try Assets.store()
        let index = try Assets.centroids()
        let pkinase = try #require(try store.family(accession: PfamID("PF00069")))
        let tyrosine = try #require(try store.family(accession: PfamID("PF07714")))

        let neighbours = index.neighbours(ofRow: pkinase.row, k: 5)
        #expect(neighbours.first?.row == tyrosine.row)
        #expect(index.similarity(pkinase.row, tyrosine.row) > 0.9)
    }

    @Test("Lysozyme classifies as Lysozyme", .timeLimit(.minutes(2)))
    func lysozymeClassifies() throws {
        let store = try Assets.store()
        let index = try Assets.centroids()
        let embedder = try Assets.proteinEmbedder()

        let vector = try embedder.embed(sequence: Probes.lysozyme)
        #expect(vector.count == 320)

        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        #expect(abs(magnitude - 1.0) < 1e-2, "model returned |v| = \(magnitude)")

        let hits = index.search(vector, k: 5)
        let families = try store.families(rows: hits.map(\.row))
        let accessions = families.map(\.accession.rawValue)
        print("lysozyme top 5: " + zip(families, hits)
            .map { "\($0.0.identifier) \(String(format: "%.3f", $0.1.probability))" }
            .joined(separator: ", "))

        #expect(accessions.contains("PF00062"), "top 5 were \(accessions)")
    }

    @Test("The Neural Engine and the CPU agree", .timeLimit(.minutes(2)))
    func computeUnitParity() throws {
        let ane = try Assets.proteinEmbedder(computeUnits: .all)
        let cpu = try Assets.proteinEmbedder(computeUnits: .cpuOnly)

        let a = try ane.embed(sequence: Probes.lysozyme)
        let b = try cpu.embed(sequence: Probes.lysozyme)

        // The whitened vector's sum of squares once overflowed float16 on the
        // Neural Engine, which returned zeros while the CPU looked perfect.
        // Check the magnitude explicitly, not just the direction.
        let magnitude = sqrt(a.reduce(0) { $0 + $1 * $1 })
        #expect(magnitude > 0.9, "Neural Engine returned |v| = \(magnitude)")

        let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        #expect(dot > 0.999, "ANE and CPU disagree, cosine \(dot)")
    }

    @Test("Top-20 search over 30k families is quick enough to feel instant")
    func searchLatency() throws {
        let index = try Assets.centroids()
        let query = index.matrix.row(1234)

        _ = index.search(query, k: 20)          // warm the mapped pages
        let started = Date()
        let rounds = 20
        for _ in 0..<rounds { _ = index.search(query, k: 20) }
        let each = Date().timeIntervalSince(started) / Double(rounds) * 1000

        // Release builds only: a debug build of Accelerate-heavy Swift is many
        // times slower and would make this assertion meaningless.
        print("centroid search: \(String(format: "%.2f", each)) ms per query")
        #expect(each < 25.0)
    }
}
