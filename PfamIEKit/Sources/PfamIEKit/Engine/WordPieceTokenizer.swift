import Foundation

/// BERT WordPiece, enough of it to tokenise a Field Guide query.
///
/// MiniLM's vocabulary is 30,522 entries and ships as `minilm_vocab.txt`, one
/// token per line in id order. This implements the uncased pipeline the model
/// was trained with: strip accents, lower case, split on punctuation, then
/// greedy longest-match-first subwording.
public struct WordPieceTokenizer: Sendable {

    public enum TokenizerError: Error, CustomStringConvertible {
        case vocabularyMissing(URL)
        case vocabularyIncomplete(String)

        public var description: String {
            switch self {
            case .vocabularyMissing(let url):
                return "The text vocabulary is missing at \(url.lastPathComponent)."
            case .vocabularyIncomplete(let token):
                return "The text vocabulary has no '\(token)' entry."
            }
        }
    }

    public static let contextLength = 256

    private let ids: [String: Int32]
    private let clsID: Int32
    private let sepID: Int32
    private let padID: Int32
    private let unkID: Int32

    /// The longest word this will try to subword before giving up and emitting
    /// `[UNK]`. Matches the reference implementation.
    private let maxCharactersPerWord = 100

    public init(vocabularyURL: URL) throws {
        guard let text = try? String(contentsOf: vocabularyURL, encoding: .utf8) else {
            throw TokenizerError.vocabularyMissing(vocabularyURL)
        }
        var table: [String: Int32] = [:]
        for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let token = String(line)
            if token.isEmpty && index > 0 { continue }
            table[token] = Int32(index)
        }
        func require(_ token: String) throws -> Int32 {
            guard let id = table[token] else { throw TokenizerError.vocabularyIncomplete(token) }
            return id
        }
        self.ids = table
        self.clsID = try require("[CLS]")
        self.sepID = try require("[SEP]")
        self.padID = try require("[PAD]")
        self.unkID = try require("[UNK]")
    }

    public struct Encoding: Sendable {
        public let inputIDs: [Int32]
        public let attentionMask: [Int32]
        public let tokenCount: Int
    }

    /// Splits text the way BERT's basic tokeniser does, before subwording.
    static func basicTokens(_ text: String) -> [String] {
        let folded = text.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
        var tokens: [String] = []
        var current = ""
        for character in folded {
            if character.isWhitespace {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if character.isLetter || character.isNumber {
                current.append(character)
            } else {
                // Punctuation becomes its own token: "haem-binding" has to
                // reach the vocabulary as haem, -, binding.
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(character))
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private func subword(_ word: String) -> [Int32] {
        let characters = Array(word)
        guard characters.count <= maxCharactersPerWord else { return [unkID] }

        var pieces: [Int32] = []
        var start = 0
        while start < characters.count {
            var end = characters.count
            var matched: Int32?
            while start < end {
                var candidate = String(characters[start..<end])
                if start > 0 { candidate = "##" + candidate }
                if let id = ids[candidate] { matched = id; break }
                end -= 1
            }
            guard let id = matched else { return [unkID] }
            pieces.append(id)
            start = end
        }
        return pieces
    }

    public func encode(_ text: String) -> Encoding {
        var tokens: [Int32] = [clsID]
        for word in Self.basicTokens(text) {
            if tokens.count >= Self.contextLength - 1 { break }
            tokens.append(contentsOf: subword(word))
        }
        if tokens.count > Self.contextLength - 1 {
            tokens = Array(tokens[0..<(Self.contextLength - 1)])
        }
        tokens.append(sepID)

        let realCount = tokens.count
        var inputIDs = tokens
        inputIDs.append(contentsOf: Array(repeating: padID, count: Self.contextLength - realCount))
        var attention = Array(repeating: Int32(1), count: realCount)
        attention.append(contentsOf: Array(repeating: Int32(0), count: Self.contextLength - realCount))

        return Encoding(inputIDs: inputIDs, attentionMask: attention, tokenCount: realCount)
    }
}
