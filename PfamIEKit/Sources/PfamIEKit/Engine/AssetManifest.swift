import Foundation

/// The forge's description of what it produced.
///
/// The app reads shapes from here rather than hard-coding 30,031 x 320, so a
/// re-forged Pfam release is a resource swap and not a code change. Loading
/// asserts the matrices are the size the manifest claims.
public struct AssetManifest: Sendable, Codable {

    public struct FileEntry: Sendable, Codable {
        public let file: String
        public let shape: [Int]
        public let dtype: String
        public let bytes: Int
    }

    /// Fitted against real UniProt proteins, not held-out Pfam seed sequences.
    /// The seed figures are carried too, clearly labelled, because the gap
    /// between them is the whole reason this app quotes the numbers it does.
    public struct CalibrationEntry: Sendable, Codable {
        public let temperature: Float
        public let confidence_high: Float
        public let confidence_mid: Float
        public let abstain_probability: Float
        public let real_proteins: Int
        public let real_top1: Float
        public let real_top5: Float
        public let real_top20: Float
        public let accuracy_high_band: Float
        public let accuracy_mid_band: Float
        public let accuracy_low_band: Float
        public let accuracy_none_band: Float
        public let fraction_high: Float
        public let fraction_mid: Float
        public let fraction_low: Float
        public let fraction_none: Float
        public let heldout_seed_top1: Float
        public let heldout_seed_top5: Float
    }

    public let forge_date: String
    public let pfam_release: String
    public let families: Int
    public let protein_dim: Int
    public let text_dim: Int
    public let files: [FileEntry]
    public let calibration: CalibrationEntry

    public var calibrationSettings: Calibration {
        Calibration(
            temperature: calibration.temperature,
            highThreshold: calibration.confidence_high,
            midThreshold: calibration.confidence_mid,
            abstainThreshold: calibration.abstain_probability,
            realTop1: calibration.real_top1,
            realTop5: calibration.real_top5,
            bandAccuracy: [
                .high: calibration.accuracy_high_band,
                .mid: calibration.accuracy_mid_band,
                .low: calibration.accuracy_low_band,
                .none: calibration.accuracy_none_band,
            ]
        )
    }

    /// The storage format the forge used for a matrix, so the app loads what
    /// is actually on disk rather than what it was compiled expecting.
    public func dtype(of file: String) -> String {
        files.first { $0.file == file }?.dtype ?? "float16"
    }

    public static func load(from url: URL) throws -> AssetManifest {
        try JSONDecoder().decode(AssetManifest.self, from: Data(contentsOf: url))
    }
}
