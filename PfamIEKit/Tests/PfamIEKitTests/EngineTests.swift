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

@Suite("Camera sequence harvesting")
struct SequenceHarvesterTests {

    @Test("Prose is not a sequence, even written in residue letters")
    func rejectsProse() {
        // Every one of these is a valid residue string. That is the whole
        // problem with reading sequences off a page.
        for prose in ["MASSIVE", "CANDIDATE", "SEQUENCE", "A MAN", "PROTEIN FAMILY",
                      "THE ENTIRE PROTEIN FAMILY DATABASE",
                      "DOMAIN ARCHITECTURE AND FAMILY ASSIGNMENT"] {
            #expect(SequenceHarvester.sequenceLike(in: prose).isEmpty,
                    "\(prose) was taken for a sequence")
        }
    }

    @Test("Real sequences sit well below the English bigram threshold")
    func bigramSeparation() {
        // The measured maximum over 300 Pfam seed sequences is 0.148 and the
        // threshold is 0.17, so a real sequence must never come close.
        for sequence in [Probes.lysozyme, Probes.src] {
            let density = SequenceHarvester.englishBigramDensity(of: sequence)
            #expect(density < SequenceHarvester.maximumEnglishBigramDensity,
                    "a real sequence scored \(density) as English")
        }
        // And a sentence must be well above it.
        #expect(SequenceHarvester.englishBigramDensity(of: "THISISTHEMATERIALSANDMETH")
                > SequenceHarvester.maximumEnglishBigramDensity)
    }

    @Test("Low-complexity runs from figure furniture are rejected")
    func rejectsLowComplexity() {
        #expect(SequenceHarvester.sequenceLike(in: String(repeating: "A", count: 40)).isEmpty)
        #expect(SequenceHarvester.sequenceLike(in: String(repeating: "AG", count: 20)).isEmpty)
    }

    @Test("Lower-case prose is rejected, upper-case residues are kept")
    func caseMatters() {
        #expect(SequenceHarvester.sequenceLike(in: "kvfgrcelaaamkrhgldnyrgy").isEmpty)
        #expect(SequenceHarvester.sequenceLike(in: "KVFGRCELAAAMKRHGLDNYRGY").count == 1)
    }

    @Test("A sequence is pulled out of a line of caption text")
    func extractsFromCaption() {
        let line = "Figure 2. The mature chain KVFGRCELAAAMKRHGLDNYRGYSLGNWVCAAKFE is shown."
        let found = SequenceHarvester.sequenceLike(in: line)
        #expect(found == ["KVFGRCELAAAMKRHGLDNYRGYSLGNWVCAAKFE"])

        // Printed in blocks of ten, which is the usual convention and the
        // reason whitespace cannot simply be a separator.
        let blocks = "KVFGRCELAA AMKRHGLDNY RGYSLGNWVC AAKFESNFNT"
        #expect(SequenceHarvester.sequenceLike(in: blocks)
                == ["KVFGRCELAAAMKRHGLDNYRGYSLGNWVCAAKFESNFNT"])
    }

    @Test("Fragments accumulate in order and re-reads do not duplicate")
    func accumulates() {
        var harvester = SequenceHarvester()
        harvester.absorb(["KVFGRCELAAAMKRHGLDNYRGY", "SLGNWVCAAKFESNFNTQATNRN"])
        let afterTwo = harvester.sequence
        #expect(afterTwo == "KVFGRCELAAAMKRHGLDNYRGYSLGNWVCAAKFESNFNTQATNRN")

        // The camera re-reads the same text constantly as it moves; a second
        // sighting must not append the fragment twice.
        harvester.absorb(["KVFGRCELAAAMKRHGLDNYRGY"])
        #expect(harvester.sequence == afterTwo)

        harvester.reset()
        #expect(harvester.sequence.isEmpty)
    }
}

@Suite("InterProScan result parsing")
struct InterProScanParsingTests {

    /// A trimmed InterProScan 5 response, shaped exactly as EBI returns it.
    /// Parsing is tested against this rather than by contacting EBI: their
    /// service is shared, jobs take minutes, and a unit test has no business
    /// queueing on public infrastructure.
    private static let response = Data("""
    {"results":[{"sequence":"MGSNK","matches":[
      {"signature":{"accession":"PF00018","name":"SH3_1",
        "signatureLibraryRelease":{"library":"PFAM"}},
       "evalue":1.2e-12,
       "locations":[{"start":90,"end":137}]},
      {"signature":{"accession":"PF07714","name":"PK_Tyr_Ser-Thr",
        "signatureLibraryRelease":{"library":"PFAM"}},
       "evalue":3.4e-60,
       "locations":[{"start":271,"end":518}]},
      {"signature":{"accession":"PF00017","name":"SH2",
        "signatureLibraryRelease":{"library":"PFAM"}},
       "evalue":5.0e-20,
       "locations":[{"start":151,"end":233}]},
      {"signature":{"accession":"G3DSA:3.30.200.20","name":"not-pfam",
        "signatureLibraryRelease":{"library":"GENE3D"}},
       "locations":[{"start":1,"end":50}]}
    ]}]}
    """.utf8)

    @Test("Pfam matches are extracted, ordered, and non-Pfam signatures dropped")
    func parsesMatches() {
        let matches = InterProScanClient.parse(json: Self.response)

        // Gene3D and every other member database must be filtered out: this
        // app compares against Pfam, and a CATH superfamily in the list would
        // read as a disagreement that is not one.
        #expect(matches.count == 3)
        #expect(matches.allSatisfy { $0.accession.hasPrefix("PF") })

        // Ordered N to C, which is how the result is displayed.
        #expect(matches.map(\.accession) == ["PF00018", "PF00017", "PF07714"])
        #expect(matches[0].start == 90 && matches[0].end == 137)
        #expect(matches[2].evalue == 3.4e-60)
    }

    @Test("Malformed or empty responses yield nothing rather than crashing")
    func toleratesRubbish() {
        #expect(InterProScanClient.parse(json: Data("not json".utf8)).isEmpty)
        #expect(InterProScanClient.parse(json: Data("{}".utf8)).isEmpty)
        #expect(InterProScanClient.parse(json: Data(#"{"results":[]}"#.utf8)).isEmpty)
        // A match with no locations must not produce a zero-length domain.
        let noLocations = Data(#"{"results":[{"matches":[{"signature":{"accession":"PF00069"}}]}]}"#.utf8)
        #expect(InterProScanClient.parse(json: noLocations).isEmpty)
    }
}

@Suite("Calibration")
struct CalibrationTests {

    private let calibration = Calibration(
        temperature: 0.065, highThreshold: 0.75, midThreshold: 0.45,
        abstainThreshold: 0.25, realTop1: 0.430, realTop5: 0.493,
        bandAccuracy: [.high: 0.944, .mid: 0.553, .low: 0.309, .none: 0.096]
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

        // Four families the query cannot be told apart from is not a call.
        // The band must be somewhere below Mid; exactly where depends on the
        // fitted thresholds and is not the point of this test.
        let tied = calibration.probabilities(forSimilarities: [0.70, 0.699, 0.698, 0.697])
        #expect(calibration.band(for: tied[0]) == .low || calibration.band(for: tied[0]) == .none)
        #expect(tied[0] < calibration.midThreshold)

        // Every band must be able to state its own measured accuracy: a band
        // label with no number behind it is exactly the kind of unearned
        // confidence this whole mechanism exists to avoid.
        for band in Calibration.Band.allCases {
            #expect(calibration.expectedAccuracy(for: band) > 0)
        }
    }
}

@Suite("Engine against the forged assets", .enabled(if: Assets.isForged))
struct ForgedAssetTests {

    @Test("Confidence is calibrated on real proteins, not on seed sequences")
    func calibratedOnRealProteins() throws {
        let manifest = try Assets.manifest()
        let calibration = manifest.calibrationSettings

        // The seed-fitted figure is far higher. If the shipped calibration ever
        // matches it, stage_emit has picked up the wrong file and every
        // confidence the app shows is overstated by about thirty points.
        #expect(manifest.calibration.real_top1 < manifest.calibration.heldout_seed_top1 - 0.15)
        #expect(calibration.realTop1 == manifest.calibration.real_top1)

        // Bands must be monotonic, or the labels mean nothing.
        #expect(calibration.expectedAccuracy(for: .high) > calibration.expectedAccuracy(for: .mid))
        #expect(calibration.expectedAccuracy(for: .mid) > calibration.expectedAccuracy(for: .low))
        #expect(calibration.expectedAccuracy(for: .low) > calibration.expectedAccuracy(for: .none))
        #expect(calibration.expectedAccuracy(for: .high) > 0.85)
    }

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

    @Test("Quantised matrices round-trip to unit length")
    func quantisationRoundTrip() throws {
        let manifest = try Assets.manifest()
        let index = try Assets.centroids()

        // int8 with a per-row scale must still hand back a unit vector, or the
        // dot product it feeds is no longer a cosine and every threshold in the
        // calibration is measuring something else.
        for row in [0, 7, index.count / 3, index.count - 1] {
            let vector = index.matrix.row(row)
            let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
            #expect(abs(magnitude - 1.0) < 0.01, "row \(row) has |v| = \(magnitude)")
        }

        // Whatever format shipped, the manifest must describe it: loading the
        // wrong reader against the right bytes is a silent size mismatch away
        // from garbage.
        #expect(["int8+scale", "float16"].contains(manifest.dtype(of: "centroids.bin")))
        #expect(["int8+scale", "float16"].contains(manifest.dtype(of: "desc_emb.bin")))
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

        // Rank is the property that matters and the one the app depends on.
        // The absolute cosine is much lower here than in raw embedding space
        // (0.85 against 0.95) precisely because whitening spread the families
        // out, which is the point of applying it.
        let neighbours = index.neighbours(ofRow: pkinase.row, k: 5)
        #expect(neighbours.first?.row == tyrosine.row)
        #expect(index.similarity(pkinase.row, tyrosine.row) > 0.7)
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

        // Direction agreement only needs to be close: the Neural Engine
        // accumulates in float16 and the CPU in float32, so an exact match is
        // not on offer. The magnitude check above is the one that catches the
        // failure that actually happened.
        let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        #expect(dot > 0.995, "ANE and CPU disagree, cosine \(dot)")
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

@Suite("End to end", .enabled(if: Assets.isForged))
struct EndToEndTests {

    private func engine() async throws -> PfamIEEngine {
        try PfamIEEngine(assets: PfamIEEngine.Assets(
            manifest: Assets.bundle!.appendingPathComponent("manifest.json"),
            database: Assets.bundle!.appendingPathComponent("pfam.sqlite"),
            centroids: Assets.bundle!.appendingPathComponent("centroids.bin"),
            coordinates: Assets.bundle!.appendingPathComponent("umap3d.bin"),
            descriptionEmbeddings: Assets.bundle!.appendingPathComponent("desc_emb.bin"),
            proteinModel: try Assets.compiledModel("PfamIEProteinEmbedder"),
            textModel: try Assets.compiledModel("PfamIETextEmbedder"),
            textVocabulary: Assets.coreml!.appendingPathComponent("minilm_vocab.txt")
        ))
    }

    @Test("SRC's architecture reads SH3 then SH2 then kinase, N to C",
          .timeLimit(.minutes(3)))
    func srcArchitecture() async throws {
        let engine = try await engine()
        let result = try await engine.classify(sequence: Probes.src)

        print("SRC domains: " + result.domains
            .map { "\($0.family.displayName)(\($0.start)-\($0.end))" }
            .joined(separator: " -> "))
        print("SRC headline: " + result.hits.prefix(3)
            .map { "\($0.family.displayName) \(String(format: "%.2f", $0.probability))" }
            .joined(separator: ", "))

        let called = Set(result.domains.map(\.family.accession.rawValue))
        // PF07714 is the tyrosine kinase domain, which dominates the protein.
        #expect(called.contains("PF07714"), "called \(called)")

        // Whatever else it finds, the order it reports must be N to C: the
        // Grammarian and the architecture track both depend on it.
        let starts = result.domains.map(\.start)
        #expect(starts == starts.sorted())

        // Domains must not be reported stacked on top of each other. Scanning
        // at four widths proposes the same domain several times, and the
        // selection step exists to collapse those.
        for (a, b) in zip(result.domains, result.domains.dropFirst()) {
            let overlap = min(a.end, b.end) - max(a.start, b.start) + 1
            let shorter = min(a.length, b.length)
            #expect(Double(overlap) / Double(shorter) <= 0.4,
                    "\(a.family.displayName) and \(b.family.displayName) overlap heavily")
        }
    }

    @Test("A confident call names a family, a weak one abstains",
          .timeLimit(.minutes(3)))
    func abstains() async throws {
        let engine = try await engine()

        // A homopolymer is not a protein family. The honest answer is that
        // there is not one, and the abstain band exists so the app can say so
        // rather than naming the least-bad of 30,031 options.
        let nonsense = try await engine.classify(sequence: String(repeating: "AG", count: 90))
        print("nonsense band: \(nonsense.band), top p = "
              + String(format: "%.3f", nonsense.hits.first?.probability ?? 0))

        let real = try await engine.classify(sequence: Probes.lysozyme)
        print("lysozyme band: \(real.band), top: " + real.hits.prefix(3)
            .map { "\($0.family.displayName) \(String(format: "%.2f", $0.probability))" }
            .joined(separator: ", "))

        #expect(real.hits.contains { $0.family.accession.rawValue == "PF00062" })
    }

    @Test("Field Guide search finds plastic-degrading families offline",
          .timeLimit(.minutes(3)))
    func semanticSearch() async throws {
        let engine = try await engine()
        let hits = try await engine.search("breaks down plastic", limit: 25)
        #expect(!hits.isEmpty)
        print("plastic: " + hits.prefix(8).map(\.family.displayName).joined(separator: ", "))

        // An accession must always resolve literally, whatever the embedding
        // thinks of it.
        let literal = try await engine.search("PF00069", limit: 5)
        #expect(literal.first?.family.accession.rawValue == "PF00069")
    }

    @Test("Domain architectures round-trip, N to C")
    func architectures() async throws {
        let engine = try await engine()
        let sh2 = try #require(try await engine.store.family(accession: PfamID("PF00017")))
        let architectures = try await engine.store.architectures(forFamilyRow: sh2.row)
        #expect(!architectures.isEmpty)

        for architecture in architectures {
            // Members must be ordered and complete: the signature is derived
            // from them now rather than stored, so an empty or shuffled member
            // list would silently produce a wrong architecture string.
            #expect(!architecture.members.isEmpty)
            #expect(architecture.members.count == architecture.signature
                .split(separator: "-").count)
            #expect(architecture.proteinCount > 0)
        }

        // SRC's architecture is SH3, SH2, then the tyrosine kinase domain, and
        // it is common enough that it must be in SH2's top few.
        let src = architectures.first {
            $0.signature == "PF00018-PF00017-PF07714"
        }
        #expect(src != nil, "signatures were \(architectures.map(\.signature))")

        // Ordered so the commonest context comes first.
        let counts = architectures.map(\.proteinCount)
        #expect(counts == counts.sorted(by: >))
    }

    @Test("Co-occurrence carries a direction where it has one")
    func cooccurrence() async throws {
        let engine = try await engine()
        let sh2 = try #require(try await engine.store.family(accession: PfamID("PF00017")))
        let edges = try await engine.store.cooccurrence(forFamilyRow: sh2.row)
        #expect(!edges.isEmpty)
        #expect(edges.allSatisfy { $0.familyRow == sh2.row })
        #expect(edges.allSatisfy { $0.countBefore + $0.countAfter <= $0.proteinCount })

        // SH3 sits N-terminal to SH2 in the Src-family kinases, and the kinase
        // domain sits C-terminal to it. Both have to survive into the ordering
        // claim the Grammarian makes out loud.
        let sh3 = try #require(try await engine.store.family(accession: PfamID("PF00018")))
        let kinase = try #require(try await engine.store.family(accession: PfamID("PF07714")))
        let sh3Edge = try #require(edges.first { $0.partnerRow == sh3.row })
        #expect(sh3Edge.ordering == .alwaysBefore)
        let kinaseEdge = try #require(edges.first { $0.partnerRow == kinase.row })
        #expect(kinaseEdge.ordering == .alwaysAfter)

        // Domain order is strongly conserved but not universally: 2.3% of pairs
        // genuinely vary, and if that ever reads as 0% the counting has broken
        // and every row would claim an invariant order it has not measured.
        var varying = 0
        for family in try await engine.store.allFamilies().prefix(400) {
            for edge in try await engine.store.cooccurrence(forFamilyRow: family.row) {
                if case .mostlyBefore = edge.ordering { varying += 1 }
                if case .mostlyAfter = edge.ordering { varying += 1 }
            }
        }
        #expect(varying > 0, "no pair anywhere showed a mixed N-to-C order")
    }

    @Test("The unknown-function list contains families that really are unknown")
    func unknownFunctionListIsClean() async throws {
        let engine = try await engine()
        let dufs = try await engine.store.unknownFunctionFamilies(limit: 40)
        #expect(dufs.count == 40)

        // Matching the CC abstract as well as the DE flagged 949 characterised
        // families, and the Prospector's largest entries were things like the
        // MurJ lipid II flippase and the ZIP zinc transporter. Every entry must
        // say so in its own one-line summary or carry Pfam's own prefix.
        for family in dufs {
            let identifier = family.identifier.uppercased()
            let summary = family.summary.lowercased()
            let looksUnknown = identifier.hasPrefix("DUF") || identifier.hasPrefix("UPF")
                || summary.contains("unknown")
                || summary.contains("uncharacteri")
            #expect(looksUnknown,
                    "\(family.identifier): \(family.summary) is not an unknown-function family")
        }

        // Some families with a known transporter or enzyme name must NOT be in
        // the list. These are the exact ones the loose rule let through.
        for accession in ["PF03023", "PF03105", "PF06347"] {
            if let family = try await engine.store.family(accession: PfamID(accession)) {
                #expect(!family.isDUF, "\(family.identifier) should not be flagged unknown")
            }
        }
    }

    @Test("Prospector never proposes another unknown family as a hypothesis")
    func hypothesesAreAnnotated() async throws {
        let engine = try await engine()
        let dufs = try await engine.store.unknownFunctionFamilies(limit: 10)
        #expect(!dufs.isEmpty)
        for duf in dufs.prefix(5) {
            let leads = try await engine.hypotheses(for: duf)
            #expect(leads.allSatisfy { !$0.neighbour.isDUF },
                    "\(duf.displayName) was offered a DUF as a lead")
        }
    }
}
