import PfamIEKit
import SwiftUI

/// One screen: what the phone last classified, and how confident it was.
struct WatchGlanceView: View {
    @Environment(WatchLink.self) private var link

    private var theme: Theme { .dark }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if link.latest.accession.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "wand.and.stars")
                                .font(.title2)
                                .foregroundStyle(theme.accentNova)
                            Text("Classify something on your phone and it appears here.")
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(theme.inkSecondary)
                        }
                        .padding(.top, 20)
                    } else {
                        gauge
                        Text(link.latest.family)
                            .font(.system(.headline, design: .rounded))
                            .multilineTextAlignment(.center)
                        Text(link.latest.accession)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.inkSecondary)
                        if let clan = link.latest.clan {
                            Text(clan)
                                .font(.caption2)
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(theme.accentPulsar.opacity(0.2), in: Capsule())
                                .foregroundStyle(theme.accentPulsar)
                        }
                        Text("\(link.latest.residueCount) residues")
                            .font(.caption2)
                            .foregroundStyle(theme.inkSecondary)
                    }
                }
                .padding(.horizontal, 6)
            }
            .navigationTitle("PfamIE")
        }
    }

    private var gauge: some View {
        Gauge(value: min(max(link.latest.probability, 0), 1)) {
            EmptyView()
        } currentValueLabel: {
            Text(link.latest.probability, format: .percent.precision(.fractionLength(0)))
                .font(.system(.title3, design: .rounded, weight: .semibold))
        }
        .gaugeStyle(.accessoryCircular)
        .tint(bandColour)
        .scaleEffect(1.15)
        .padding(.top, 6)
    }

    private var bandColour: Color {
        switch link.latest.band {
        case "high": return theme.confidenceHigh
        case "mid": return theme.confidenceMid
        case "low": return theme.confidenceLow
        default: return theme.inkSecondary
        }
    }
}
