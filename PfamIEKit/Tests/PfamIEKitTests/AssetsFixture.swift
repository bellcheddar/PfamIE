import CoreML
import Foundation
import Testing
@testable import PfamIEKit

/// Locates the forge's output and compiles the Core ML packages once per run.
///
/// Tests that need the real 30,031-family assets look here. If the forge has
/// not been run, they skip with a clear reason rather than failing: a fresh
/// clone has the code but not the baked data.
enum Assets {

    /// `assets/` in the repository, or wherever PFAMIE_ASSETS points.
    static let root: URL? = {
        if let override = ProcessInfo.processInfo.environment["PFAMIE_ASSETS"] {
            return URL(fileURLWithPath: override)
        }
        // Tests/PfamIEKitTests/ -> Tests/ -> PfamIEKit/ -> PfamIE/
        var url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        url.appendPathComponent("assets")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }()

    static var bundle: URL? { root?.appendingPathComponent("bundle") }
    static var coreml: URL? { root?.appendingPathComponent("coreml") }

    static var isForged: Bool {
        guard let bundle else { return false }
        return ["manifest.json", "centroids.bin", "pfam.sqlite"].allSatisfy {
            FileManager.default.fileExists(atPath: bundle.appendingPathComponent($0).path)
        }
    }

    static func manifest() throws -> AssetManifest {
        try AssetManifest.load(from: bundle!.appendingPathComponent("manifest.json"))
    }

    static func store() throws -> PfamStore {
        try PfamStore(url: bundle!.appendingPathComponent("pfam.sqlite"))
    }

    static func centroids() throws -> CentroidIndex {
        let m = try manifest()
        let matrix = try EmbeddingMatrixLoader.load(
            contentsOf: bundle!.appendingPathComponent("centroids.bin"),
            rows: m.families, columns: m.protein_dim,
            dtype: m.dtype(of: "centroids.bin")
        )
        return CentroidIndex(matrix: matrix, calibration: m.calibrationSettings)
    }

    /// Compiled mlmodelc paths, cached so the whole suite pays the compile once.
    nonisolated(unsafe) private static var compiled: [String: URL] = [:]
    private static let compileLock = NSLock()

    static func compiledModel(_ name: String) throws -> URL {
        compileLock.lock()
        defer { compileLock.unlock() }
        if let existing = compiled[name] { return existing }
        let source = coreml!.appendingPathComponent("\(name).mlpackage")
        let url = try MLModel.compileModel(at: source)
        compiled[name] = url
        return url
    }

    static func proteinEmbedder(computeUnits: MLComputeUnits = .all) throws -> ProteinEmbedder {
        try ProteinEmbedder(
            modelURL: compiledModel("PfamIEProteinEmbedder"),
            computeUnits: computeUnits,
            dimensions: try manifest().protein_dim
        )
    }
}

/// Sequences used across the suite. Real proteins, chosen because their Pfam
/// content is not in doubt.
enum Probes {
    /// Hen egg-white lysozyme, P00698, mature chain. Pfam PF00062 (Lysozyme).
    static let lysozyme = """
        KVFGRCELAAAMKRHGLDNYRGYSLGNWVCAAKFESNFNTQATNRNTDGSTDYGILQINSRWWCNDGRTPGS\
        RNLCNIPCSALLSSDITASVNCAKKIVSDGNGMNAWVAWRNRCKGTDVQAWIRGCRL
        """

    /// Human SRC kinase, P12931. Architecture is SH3 (PF00018), SH2 (PF00017)
    /// then the tyrosine kinase domain (PF07714), N to C.
    static let src = """
        MGSNKSKPKDASQRRRSLEPAENVHGAGGGAFPASQTPSKPASADGHRGPSAAFAPAAAEPKLFGGFNSSDT\
        VTSPQRAGPLAGGVTTFVALYDYESRTETDLSFKKGERLQIVNNTEGDWWLAHSLSTGQTGYIPSNYVAPSD\
        SIQAEEWYFGKITRRESERLLLNAENPRGTFLVRESETTKGAYCLSVSDFDNAKGLNVKHYKIRKLDSGGFY\
        ITSRTQFNSLQQLVAYYSKHADGLCHRLTTVCPTSKPQTQGLAKDAWEIPRESLRLEVKLGQGCFGEVWMGT\
        WNGTTRVAIKTLKPGTMSPEAFLQEAQVMKKLRHEKLVQLYAVVSEEPIYIVTEYMSKGSLLDFLKGETGKY\
        LRLPQLVDMAAQIASGMAYVERMNYVHRDLRAANILVGENLVCKVADFGLARLIEDNEYTARQGAKFPIKWT\
        APEAALYGRFTIKSDVWSFGILLTELTTKGRVPYPGMVNREVLDQVERGYRMPCPPECPESLHDLMCQCWRK\
        EPEERPTFEYLQAFLEDYFTSTEPQYQPGENL
        """
}
