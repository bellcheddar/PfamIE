import CoreML
import Foundation
import Testing
@testable import PfamIEKit

/// Does the *built app* find its own assets?
///
/// Every other test reads from `assets/` directly, which exercises the engine
/// but not `BundledAssets`: the path logic that has to cope with Xcode
/// compiling each `.mlpackage` to a `.mlmodelc` at the bundle root while the
/// data folder is copied in as a folder reference. That resolution is exactly
/// the kind of thing that is fine in the package and broken in the app, and it
/// would present as "the app launches to an error" with the engine untouched.
@Suite("Built app bundle", .enabled(if: BuiltApp.url != nil))
struct BundleWiringTests {

    @Test("The built app resolves every asset it needs")
    func resolvesAssets() throws {
        let bundle = try #require(BuiltApp.bundle)
        let assets = try #require(BundledAssets.assets(in: bundle),
                                  "BundledAssets found no manifest in the built app")

        let manager = FileManager.default
        for (label, url) in [
            ("manifest", assets.manifest),
            ("database", assets.database),
            ("centroids", assets.centroids),
            ("coordinates", assets.coordinates),
            ("description embeddings", assets.descriptionEmbeddings),
            ("protein model", assets.proteinModel),
            ("text model", assets.textModel),
            ("text vocabulary", assets.textVocabulary),
        ] {
            #expect(manager.fileExists(atPath: url.path),
                    "\(label) not found at \(url.path)")
        }
    }

    @Test("The engine starts from the built app and classifies",
          .timeLimit(.minutes(3)))
    func classifiesFromBundle() async throws {
        let bundle = try #require(BuiltApp.bundle)
        let assets = try #require(BundledAssets.assets(in: bundle))

        let engine = try PfamIEEngine(assets: assets)
        let result = try await engine.classify(sequence: Probes.src)

        print("from bundle: " + result.hits.prefix(3)
            .map { "\($0.family.displayName) \(String(format: "%.2f", $0.probability))" }
            .joined(separator: ", "))

        #expect(result.hits.contains { $0.family.accession.rawValue == "PF07714" })
        #expect(result.band == .high)

        // The Field Guide needs the text model and the description matrix, and
        // those are the two most likely to be left out of a bundle.
        let search = try await engine.search("protein kinase", limit: 5)
        #expect(!search.isEmpty)
    }
}

enum BuiltApp {
    /// The most recently built macOS app in DerivedData, if there is one.
    static let url: URL? = {
        if let override = ProcessInfo.processInfo.environment["PFAMIE_APP"] {
            return URL(fileURLWithPath: override)
        }
        let derived = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: derived, includingPropertiesForKeys: nil
        ) else { return nil }

        for entry in entries where entry.lastPathComponent.hasPrefix("PfamIE-") {
            let candidate = entry
                .appendingPathComponent("Build/Products/Debug/PfamIE.app")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }()

    static var bundle: Bundle? { url.flatMap(Bundle.init(url:)) }
}
