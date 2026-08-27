import Foundation

/// Turns cosine similarities into a confidence the app can state out loud.
///
/// Every constant here is fitted in the forge, never guessed, and fitted
/// against *real UniProt proteins* rather than held-out Pfam seed sequences.
/// That distinction is the difference between honest and flattering: the same
/// pipeline scores 0.72 top-1 on held-out seeds and 0.43 on real proteins,
/// because seeds are trimmed to domain boundaries and drawn from the very
/// alignments the centroids were built from. Calibrated on seeds, an
/// all-alanine nonsense sequence came back at 0.51.
///
/// Measured on 625 real proteins held back from the fit:
///
///   High  (p >= 0.75)  22.7% of queries, 94.4% of them correct
///   Mid   (p >= 0.45)  19.7% of queries, 55.3% correct
///   Low   (p >= 0.25)  25.9% of queries, 30.9% correct
///   None  (p <  0.25)  31.7% of queries,  9.6% correct
///
/// The bottom band is why the Oracle can answer "no confident family": naming
/// one there would be right about one time in ten.
public struct Calibration: Sendable, Codable, Equatable {

    public enum Band: String, Sendable, Codable, CaseIterable {
        case high, mid, low, none

        public var label: String {
            switch self {
            case .high: return "High confidence"
            case .mid: return "Moderate confidence"
            case .low: return "Low confidence"
            case .none: return "No confident family"
            }
        }
    }

    public let temperature: Float
    public let highThreshold: Float
    public let midThreshold: Float
    public let abstainThreshold: Float

    /// Accuracy on real proteins, carried so the app can show its own error
    /// rate instead of asking the user to take the ranking on trust.
    public let realTop1: Float
    public let realTop5: Float

    /// Measured accuracy per band, from the forge. Not hard-coded here: a
    /// number baked into the app would silently stop matching the assets the
    /// next time Pfam is re-forged.
    public let bandAccuracy: [Band: Float]

    public init(
        temperature: Float,
        highThreshold: Float,
        midThreshold: Float,
        abstainThreshold: Float,
        realTop1: Float,
        realTop5: Float,
        bandAccuracy: [Band: Float]
    ) {
        self.temperature = temperature
        self.highThreshold = highThreshold
        self.midThreshold = midThreshold
        self.abstainThreshold = abstainThreshold
        self.realTop1 = realTop1
        self.realTop5 = realTop5
        self.bandAccuracy = bandAccuracy
    }

    /// Softmax over the shortlist, at the fitted temperature.
    ///
    /// The temperature is small (0.035), so the exponent is subtracted from its
    /// maximum first: without that, `exp(0.9 / 0.035)` overflows on its own.
    public func probabilities(forSimilarities similarities: [Float]) -> [Float] {
        guard let peak = similarities.max(), temperature > 0 else {
            return Array(repeating: 0, count: similarities.count)
        }
        var total: Float = 0
        var weights = [Float](repeating: 0, count: similarities.count)
        for (index, value) in similarities.enumerated() {
            let weight = expf((value - peak) / temperature)
            weights[index] = weight
            total += weight
        }
        guard total > 0 else { return weights }
        return weights.map { $0 / total }
    }

    public func band(for probability: Float) -> Band {
        if probability >= highThreshold { return .high }
        if probability >= midThreshold { return .mid }
        if probability >= abstainThreshold { return .low }
        return .none
    }

    /// What the app is entitled to claim for a result in this band.
    public func expectedAccuracy(for band: Band) -> Float {
        bandAccuracy[band] ?? 0
    }
}
