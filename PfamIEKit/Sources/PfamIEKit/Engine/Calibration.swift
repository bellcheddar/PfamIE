import Foundation

/// Turns cosine similarities into a confidence the app can state out loud.
///
/// Every constant here is fitted in the forge against 26,286 held-out Pfam seed
/// sequences, never guessed. Measured band behaviour at the shipped settings:
///
///   High  (p >= 0.80)  55.4% of queries, 98.4% of them correct
///   Mid   (p >= 0.50)  15.6% of queries, 65.7% correct
///   Low   (p >= 0.30)  14.3% of queries, 32.8% correct
///   None  (p <  0.30)  14.7% of queries, 14.0% correct
///
/// The bottom band is why the Oracle can answer "no confident family": naming
/// one there would be right about one time in seven.
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

    /// Held-out accuracy, carried so the app can show its own error rate
    /// instead of asking the user to take the ranking on trust.
    public let heldOutTop1: Float
    public let heldOutTop5: Float

    public init(
        temperature: Float,
        highThreshold: Float,
        midThreshold: Float,
        abstainThreshold: Float,
        heldOutTop1: Float,
        heldOutTop5: Float
    ) {
        self.temperature = temperature
        self.highThreshold = highThreshold
        self.midThreshold = midThreshold
        self.abstainThreshold = abstainThreshold
        self.heldOutTop1 = heldOutTop1
        self.heldOutTop5 = heldOutTop5
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
        switch band {
        case .high: return 0.984
        case .mid: return 0.657
        case .low: return 0.328
        case .none: return 0.140
        }
    }
}
