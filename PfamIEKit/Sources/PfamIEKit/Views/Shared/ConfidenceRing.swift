import SwiftUI

/// The calibrated confidence, drawn as a ring and stated in words.
///
/// The number is a fitted probability, not a similarity dressed up as one, so
/// the ring is allowed to say what it means: the caption carries the measured
/// accuracy of the band rather than leaving the reader to guess what 84% buys.
public struct ConfidenceRing: View {
    @Environment(\.theme) private var theme

    private let probability: Float
    private let band: Calibration.Band
    private let calibration: Calibration
    private let diameter: CGFloat

    public init(
        probability: Float,
        calibration: Calibration,
        diameter: CGFloat = 92
    ) {
        self.probability = probability
        self.calibration = calibration
        self.band = calibration.band(for: probability)
        self.diameter = diameter
    }

    private var colour: Color { theme.colour(for: band) }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .strokeBorder(theme.hairline, lineWidth: diameter * 0.09)
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.01, min(1, probability))))
                    .stroke(colour,
                            style: StrokeStyle(lineWidth: diameter * 0.09, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .shadow(color: colour.opacity(theme.isDark ? 0.55 : 0), radius: 8)

                Text(probability, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: diameter * 0.28, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                    .foregroundStyle(theme.inkPrimary)
                    .accessibilityHidden(true)
            }
            .frame(width: diameter, height: diameter)
            .animation(.snappy, value: probability)

            Text(band.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(colour)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        let percent = Int((probability * 100).rounded())
        let accuracy = Int((calibration.expectedAccuracy(for: band) * 100).rounded())
        if band == .none {
            return "No confident family. Calls this weak are right about \(accuracy) per cent of the time."
        }
        return "\(band.label), \(percent) per cent. Calls in this band are right about \(accuracy) per cent of the time."
    }
}

/// The one-line honesty note that goes under a result list.
public struct CalibrationNote: View {
    @Environment(\.theme) private var theme
    private let band: Calibration.Band
    private let calibration: Calibration

    public init(band: Calibration.Band, calibration: Calibration) {
        self.band = band
        self.calibration = calibration
    }

    public var body: some View {
        let accuracy = calibration.expectedAccuracy(for: band)
        Text(text(accuracy: accuracy))
            .font(.footnote)
            .foregroundStyle(theme.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func text(accuracy: Float) -> String {
        let percent = Int((accuracy * 100).rounded())
        switch band {
        case .high:
            return "Measured on real UniProt proteins, calls this confident are correct about \(percent)% of the time."
        case .mid:
            return "Calls at this confidence are correct about \(percent)% of the time. Worth checking against the domain architecture below."
        case .low:
            return "Calls this weak are correct about \(percent)% of the time. Treat the list as candidates, not an assignment."
        case .none:
            return "Nothing reached the confidence threshold. The nearest families are shown as leads only: at this level the top hit is right about \(percent)% of the time on real proteins."
        }
    }
}
