import Accelerate
import Foundation

/// Nearest-family search over the whitened Pfam centroid matrix.
public final class CentroidIndex: @unchecked Sendable {

    public struct Neighbour: Sendable, Hashable {
        /// Row index into every shipped matrix, and `family.row` in pfam.sqlite.
        public let row: Int
        /// Cosine similarity in whitened space, in roughly [-0.2, 1.0].
        public let similarity: Float
        /// Calibrated probability that this is the right family, over the
        /// shortlist the Oracle shows. Only meaningful for the top-k as a set.
        public let probability: Float
    }

    public let matrix: Float16Matrix
    public let calibration: Calibration

    public var count: Int { matrix.rows }
    public var dimensions: Int { matrix.columns }

    public init(matrix: Float16Matrix, calibration: Calibration) {
        self.matrix = matrix
        self.calibration = calibration
    }

    /// Top-k families for a query embedding, best first.
    ///
    /// Partial selection rather than a full sort: at 30,031 families a full
    /// sort is most of the cost of the search, and nothing above k is ever read.
    public func search(_ query: [Float], k: Int = 20) -> [Neighbour] {
        let scores = matrix.multiply(query)
        let wanted = min(k, scores.count)
        guard wanted > 0 else { return [] }

        var top = [(row: Int, score: Float)]()
        top.reserveCapacity(wanted + 1)
        var worst = -Float.greatestFiniteMagnitude

        for (row, score) in scores.enumerated() {
            if top.count < wanted {
                top.append((row, score))
                if top.count == wanted {
                    top.sort { $0.score > $1.score }
                    worst = top[wanted - 1].score
                }
            } else if score > worst {
                var insert = top.count - 1
                while insert > 0 && top[insert - 1].score < score {
                    top[insert] = top[insert - 1]
                    insert -= 1
                }
                top[insert] = (row, score)
                worst = top[wanted - 1].score
            }
        }
        if top.count < wanted { top.sort { $0.score > $1.score } }

        let probabilities = calibration.probabilities(forSimilarities: top.map(\.score))
        return zip(top, probabilities).map {
            Neighbour(row: $0.0.row, similarity: $0.0.score, probability: $0.1)
        }
    }

    /// Cosine similarity between two stored families, for "how close is this
    /// DUF to that family" questions that never touch a query embedding.
    public func similarity(_ a: Int, _ b: Int) -> Float {
        let rowA = matrix.row(a)
        let rowB = matrix.row(b)
        var result: Float = 0
        vDSP_dotpr(rowA, 1, rowB, 1, &result, vDSP_Length(matrix.columns))
        return result
    }

    /// Nearest stored families to a stored family, excluding itself.
    public func neighbours(ofRow row: Int, k: Int = 10) -> [Neighbour] {
        search(matrix.row(row), k: k + 1).filter { $0.row != row }.prefix(k).map { $0 }
    }
}
