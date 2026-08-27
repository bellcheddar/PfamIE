import Foundation

/// ESM-2's alphabet is 33 tokens, so the whole vocabulary is a literal here
/// rather than a bundled file. The order is the checkpoint's own and must not
/// be sorted: `forge/stage_coreml.py` writes `esm2_vocab.json` from the same
/// tokeniser, and `ProteinTokenizerTests` asserts the two still agree.
public struct ProteinTokenizer: Sendable {

    public static let vocabulary: [String] = [
        "<cls>", "<pad>", "<eos>", "<unk>",
        "L", "A", "G", "V", "S", "E", "R", "T", "I", "D", "P", "K", "Q", "N",
        "F", "Y", "M", "H", "W", "C", "X", "B", "U", "Z", "O",
        ".", "-", "<null_1>", "<mask>",
    ]

    public static let clsID: Int32 = 0
    public static let padID: Int32 = 1
    public static let eosID: Int32 = 2
    public static let unkID: Int32 = 3

    /// The fixed width the Core ML model was converted at.
    public static let contextLength = 512

    /// The longest residue run that fits alongside the <cls> and <eos> tokens.
    public static let maxResidues = contextLength - 2

    private static let idForResidue: [UInt8: Int32] = {
        var table: [UInt8: Int32] = [:]
        for (index, token) in vocabulary.enumerated() where token.count == 1 {
            if let byte = token.utf8.first {
                table[byte] = Int32(index)
            }
        }
        return table
    }()

    public struct Encoding: Sendable {
        /// Token ids, padded to `contextLength`.
        public let inputIDs: [Int32]
        /// 1 for real tokens (including <cls> and <eos>), 0 for padding.
        public let attentionMask: [Int32]
        /// 1 for residue positions only. `<cls>`, `<eos>` and padding are 0, so
        /// the model's mean pool covers exactly the residues that were supplied.
        public let poolMask: [Float]
        /// How many residues were actually encoded, after truncation.
        public let residueCount: Int
        /// True when the input was longer than the model's context.
        public let truncated: Bool
    }

    public init() {}

    /// Cleans a sequence to the residues ESM-2 understands.
    ///
    /// FASTA headers, whitespace, digits and gap characters are all common in
    /// pasted input; lower case is common in seed alignments. Anything that is
    /// still not a residue becomes `<unk>` rather than being dropped, so
    /// reported domain coordinates keep lining up with what the user pasted.
    public static func sanitise(_ raw: String) -> String {
        var out = String.UnicodeScalarView()
        for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.first == ">" || line.first == ";" { continue }
            for scalar in line.unicodeScalars {
                let upper = (scalar.value >= 97 && scalar.value <= 122)
                    ? Unicode.Scalar(scalar.value - 32)!
                    : scalar
                if upper.value >= 65 && upper.value <= 90 {
                    out.append(upper)
                }
            }
        }
        return String(String.UnicodeScalarView(out))
    }

    public func encode(_ sequence: String) -> Encoding {
        let cleaned = Self.sanitise(sequence)
        return encodeSanitised(cleaned)
    }

    /// Encodes an already-sanitised residue string, skipping the clean-up pass.
    public func encodeSanitised(_ residues: String) -> Encoding {
        let bytes = Array(residues.utf8)
        let truncated = bytes.count > Self.maxResidues
        let used = truncated ? Array(bytes[0..<Self.maxResidues]) : bytes

        var ids = [Int32](repeating: Self.padID, count: Self.contextLength)
        var attention = [Int32](repeating: 0, count: Self.contextLength)
        var pool = [Float](repeating: 0, count: Self.contextLength)

        ids[0] = Self.clsID
        attention[0] = 1

        for (offset, byte) in used.enumerated() {
            let position = offset + 1
            ids[position] = Self.idForResidue[byte] ?? Self.unkID
            attention[position] = 1
            pool[position] = 1
        }

        let eosPosition = used.count + 1
        ids[eosPosition] = Self.eosID
        attention[eosPosition] = 1

        return Encoding(
            inputIDs: ids,
            attentionMask: attention,
            poolMask: pool,
            residueCount: used.count,
            truncated: truncated
        )
    }
}
