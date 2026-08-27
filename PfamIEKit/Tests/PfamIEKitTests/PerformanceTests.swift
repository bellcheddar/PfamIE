import CoreML
import Foundation
import Testing
@testable import PfamIEKit

/// What the Neural Engine actually buys, measured rather than asserted.
///
/// "Runs on the ANE" is a claim a README should have a number behind. These
/// print rather than assert tight bounds, because absolute timings depend on
/// the machine, but they do assert the ordering: if the ANE is ever slower
/// than the CPU, something has fallen off it.
@Suite("Performance", .enabled(if: Assets.isForged), .serialized)
struct PerformanceTests {

    private func time(_ rounds: Int, _ body: () throws -> Void) rethrows -> Double {
        try body()                                  // warm the graph
        let started = Date()
        for _ in 0..<rounds { try body() }
        return Date().timeIntervalSince(started) / Double(rounds) * 1000
    }

    @Test("Embedding is faster on the Neural Engine than on the CPU",
          .timeLimit(.minutes(5)))
    func neuralEngineSpeedup() throws {
        let ane = try Assets.proteinEmbedder(computeUnits: .all)
        let cpu = try Assets.proteinEmbedder(computeUnits: .cpuOnly)

        let aneMs = try time(30) { _ = try ane.embed(sequence: Probes.lysozyme) }
        let cpuMs = try time(30) { _ = try cpu.embed(sequence: Probes.lysozyme) }

        print(String(format: "ESM-2 t6-8M, 512 tokens: ANE %.2f ms, CPU %.2f ms, speedup %.1fx",
                     aneMs, cpuMs, cpuMs / aneMs))
        #expect(aneMs < cpuMs, "the Neural Engine path is not faster; check it is still eligible")
    }

    @Test("A whole classification stays interactive", .timeLimit(.minutes(5)))
    func classificationLatency() async throws {
        let engine = try PfamIEEngine(assets: PfamIEEngine.Assets(
            manifest: Assets.bundle!.appendingPathComponent("manifest.json"),
            database: Assets.bundle!.appendingPathComponent("pfam.sqlite"),
            centroids: Assets.bundle!.appendingPathComponent("centroids.bin"),
            coordinates: Assets.bundle!.appendingPathComponent("umap3d.bin"),
            descriptionEmbeddings: Assets.bundle!.appendingPathComponent("desc_emb.bin"),
            proteinModel: try Assets.compiledModel("PfamIEProteinEmbedder"),
            textModel: try Assets.compiledModel("PfamIETextEmbedder"),
            textVocabulary: Assets.coreml!.appendingPathComponent("minilm_vocab.txt")
        ))

        _ = try await engine.classify(sequence: Probes.lysozyme)
        let started = Date()
        let result = try await engine.classify(sequence: Probes.src)
        let ms = Date().timeIntervalSince(started) * 1000

        print(String(format: "SRC (536 aa, %d windows across 4 scales): %.0f ms end to end",
                     result.windowsScanned, ms))
        #expect(ms < 8000)
    }

    @Test("Semantic search over 30k descriptions", .timeLimit(.minutes(5)))
    func searchLatency() throws {
        let manifest = try Assets.manifest()
        let matrix = try EmbeddingMatrixLoader.load(
            contentsOf: Assets.bundle!.appendingPathComponent("desc_emb.bin"),
            rows: manifest.families, columns: manifest.text_dim,
            dtype: manifest.dtype(of: "desc_emb.bin")
        )
        let search = try SemanticSearch(
            modelURL: try Assets.compiledModel("PfamIETextEmbedder"),
            vocabularyURL: Assets.coreml!.appendingPathComponent("minilm_vocab.txt"),
            matrix: matrix
        )
        let ms = try time(20) { _ = try search.search("breaks down plastic", limit: 40) }
        print(String(format: "Field Guide query over 30,031 descriptions: %.1f ms", ms))
        #expect(ms < 500)
    }
}
