import CoreML
import Foundation

/// Offline natural-language search over the Pfam family descriptions.
///
/// "haem-binding families that dimerise" is not a keyword query, and full-text
/// search answers it badly. The forge embedded every family's identifier,
/// summary, clan and abstract with MiniLM; this embeds the query with the same
/// model and takes the nearest descriptions.
///
/// It runs *alongside* the store's FTS rather than replacing it. Each catches
/// what the other misses: an accession or a name like "Peptidase_S8" is a
/// literal match, a description of behaviour is not.
public final class SemanticSearch: @unchecked Sendable {

    public struct Hit: Sendable, Hashable {
        public let row: Int
        public let score: Float
        /// True when the family also matched literally, which is worth showing.
        public var matchedLiterally: Bool
    }

    private let model: MLModel
    private let tokenizer: WordPieceTokenizer
    private let matrix: Float16Matrix

    public init(modelURL: URL, vocabularyURL: URL, matrix: Float16Matrix) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        self.model = try MLModel(contentsOf: modelURL, configuration: configuration)
        self.tokenizer = try WordPieceTokenizer(vocabularyURL: vocabularyURL)
        self.matrix = matrix
    }

    public func embed(query: String) throws -> [Float] {
        let encoding = tokenizer.encode(query)
        let length = WordPieceTokenizer.contextLength
        let ids = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)
        let attention = try MLMultiArray(shape: [1, NSNumber(value: length)], dataType: .int32)

        ids.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, _ in
            _ = buffer.update(fromContentsOf: encoding.inputIDs)
        }
        attention.withUnsafeMutableBufferPointer(ofType: Int32.self) { buffer, _ in
            _ = buffer.update(fromContentsOf: encoding.attentionMask)
        }

        let input = try MLDictionaryFeatureProvider(dictionary: [
            "input_ids": MLFeatureValue(multiArray: ids),
            "attention_mask": MLFeatureValue(multiArray: attention),
        ])
        let output = try model.prediction(from: input)
        guard let array = output.featureValue(for: "embedding")?.multiArrayValue else {
            return []
        }
        var vector = [Float](repeating: 0, count: array.count)
        array.withUnsafeBufferPointer(ofType: Float.self) { buffer in
            for index in 0..<array.count { vector[index] = buffer[index] }
        }
        return vector
    }

    public func search(_ query: String, limit: Int = 40) throws -> [Hit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let vector = try embed(query: trimmed)
        guard vector.count == matrix.columns else { return [] }

        let scores = matrix.multiply(vector)
        return scores.enumerated()
            .sorted { $0.element > $1.element }
            .prefix(limit)
            .map { Hit(row: $0.offset, score: $0.element, matchedLiterally: false) }
    }
}
