import CoreML
import Foundation

/// Embeds a protein sequence with the bundled ESM-2 model.
///
/// The mlpackage contains the whole recipe: masked mean pooling, the whitening
/// transform and L2 normalisation are all graph operations, so this returns a
/// finished unit vector directly comparable with a row of centroids.bin. That
/// also means the output is one-dimensional, which sidesteps Core ML's row
/// padding on multi-dimensional outputs entirely.
public final class ProteinEmbedder: @unchecked Sendable {

    public enum EmbedderError: Error, CustomStringConvertible {
        case modelMissing(URL)
        case unexpectedOutput(String)

        public var description: String {
            switch self {
            case .modelMissing(let url):
                return "The protein model is missing at \(url.lastPathComponent)."
            case .unexpectedOutput(let detail):
                return "The protein model returned something unexpected: \(detail)."
            }
        }
    }

    public let dimensions: Int
    private let model: MLModel
    private let tokenizer = ProteinTokenizer()

    /// Which processing units the loaded model was allowed to use, so the app
    /// can report honestly rather than claiming the Neural Engine on faith.
    public let computeUnits: MLComputeUnits

    public init(modelURL: URL, computeUnits: MLComputeUnits = .all, dimensions: Int = 320) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw EmbedderError.modelMissing(modelURL)
        }
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        self.model = try MLModel(contentsOf: modelURL, configuration: configuration)
        self.computeUnits = computeUnits
        self.dimensions = dimensions
    }

    /// Embeds one already-sanitised residue string.
    public func embed(residues: String) throws -> [Float] {
        try embed(encoding: tokenizer.encodeSanitised(residues))
    }

    /// Embeds free text, cleaning FASTA headers and whitespace first.
    public func embed(sequence: String) throws -> [Float] {
        try embed(encoding: tokenizer.encode(sequence))
    }

    public func embed(encoding: ProteinTokenizer.Encoding) throws -> [Float] {
        let length = ProteinTokenizer.contextLength
        let ids = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
        let attention = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
        let pool = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .float32)

        // Single-row arrays, so a linear write is safe here. Anything with more
        // than one row must go through `strides`, because Core ML pads them.
        ids.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, _ in
            _ = buffer.update(fromContentsOf: encoding.inputIDs)
        }
        attention.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, _ in
            _ = buffer.update(fromContentsOf: encoding.attentionMask)
        }
        pool.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            _ = buffer.update(fromContentsOf: encoding.poolMask)
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: ids),
            "attention_mask": MLFeatureValue(multiArray: attention),
            "pool_mask": MLFeatureValue(multiArray: pool),
        ])

        let output = try model.prediction(from: input)
        guard let array = output.featureValue(for: "embedding")?.multiArrayValue else {
            throw EmbedderError.unexpectedOutput("no 'embedding' feature")
        }
        guard array.count == dimensions else {
            throw EmbedderError.unexpectedOutput("\(array.count) values, expected \(dimensions)")
        }

        var vector = [Float](repeating: 0, count: dimensions)
        array.withUnsafeBufferPointer(ofType: Float.self) { buffer in
            for index in 0..<dimensions { vector[index] = buffer[index] }
        }
        return vector
    }

    /// Embeds several sequences in order.
    public func embed(residueStrings: [String]) throws -> [[Float]] {
        try residueStrings.map { try embed(residues: $0) }
    }
}
