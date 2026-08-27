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

    public struct CalibrationEntry: Sendable, Codable {
        public let temperature: Float
        public let confidence_high: Float
        public let confidence_mid: Float
        public let abstain_probability: Float
        public let heldout_top1: Float
        public let heldout_top5: Float
        public let heldout_top20: Float
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
            heldOutTop1: calibration.heldout_top1,
            heldOutTop5: calibration.heldout_top5
        )
    }

    public static func load(from url: URL) throws -> AssetManifest {
        try JSONDecoder().decode(AssetManifest.self, from: Data(contentsOf: url))
    }
}
