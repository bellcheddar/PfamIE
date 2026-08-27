import Foundation

/// Finds the forged assets inside an app bundle.
///
/// Xcode compiles each `.mlpackage` into a `.mlmodelc` at the bundle root and
/// copies `assets/bundle` in as a folder reference, so the two halves land in
/// different places. This is the one place that knows that.
public enum BundledAssets {

    /// The folder holding pfam.sqlite and the .bin matrices.
    public static func dataDirectory(in bundle: Bundle = .main) -> URL? {
        if let url = bundle.url(forResource: "bundle", withExtension: nil),
           FileManager.default.fileExists(
               atPath: url.appendingPathComponent("manifest.json").path
           ) {
            return url
        }
        // Flat layout: everything copied to the bundle root.
        if let manifest = bundle.url(forResource: "manifest", withExtension: "json") {
            return manifest.deletingLastPathComponent()
        }
        return nil
    }

    public static func assets(in bundle: Bundle = .main) -> PfamIEEngine.Assets? {
        guard let data = dataDirectory(in: bundle) else { return nil }
        let root = bundle.bundleURL
        let resources = bundle.resourceURL ?? root

        func model(_ name: String) -> URL {
            if let url = bundle.url(forResource: name, withExtension: "mlmodelc") { return url }
            return resources.appendingPathComponent("\(name).mlmodelc")
        }

        return PfamIEEngine.Assets(
            manifest: data.appendingPathComponent("manifest.json"),
            database: data.appendingPathComponent("pfam.sqlite"),
            centroids: data.appendingPathComponent("centroids.bin"),
            coordinates: data.appendingPathComponent("umap3d.bin"),
            descriptionEmbeddings: data.appendingPathComponent("desc_emb.bin"),
            proteinModel: model("PfamIEProteinEmbedder"),
            textModel: model("PfamIETextEmbedder"),
            textVocabulary: bundle.url(forResource: "minilm_vocab", withExtension: "txt")
                ?? resources.appendingPathComponent("minilm_vocab.txt")
        )
    }
}
