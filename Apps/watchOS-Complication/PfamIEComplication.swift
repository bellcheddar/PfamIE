import SwiftUI
import WidgetKit

/// The watch complication: the last family the phone classified, on the face.
///
/// It reads the same App Group defaults the watch app writes, because a widget
/// extension has its own container and `UserDefaults.standard` in here would
/// be a different, always-empty store. That is the classic way a complication
/// ships showing a placeholder forever.
@main
struct PfamIEComplicationBundle: WidgetBundle {
    var body: some Widget {
        LastClassificationComplication()
    }
}

struct LastClassificationComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PfamIELastClassification",
                            provider: LastClassificationProvider()) { entry in
            ComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Last classification")
        .description("The family your phone last identified, and how confident it was.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular,
        ])
    }
}

struct LastClassificationEntry: TimelineEntry {
    let date: Date
    let family: String
    let accession: String
    let probability: Double
    let band: String
    let isPlaceholder: Bool

    static let placeholder = LastClassificationEntry(
        date: .now, family: "Pkinase", accession: "PF00069",
        probability: 0.94, band: "high", isPlaceholder: true
    )

    static let empty = LastClassificationEntry(
        date: .now, family: "No scan yet", accession: "",
        probability: 0, band: "none", isPlaceholder: true
    )
}

struct LastClassificationProvider: TimelineProvider {
    /// Must match the App Group on both the watch app and this extension.
    static let suite = "group.com.mdeller.pfamie"

    func placeholder(in context: Context) -> LastClassificationEntry { .placeholder }

    func getSnapshot(in context: Context,
                     completion: @escaping (LastClassificationEntry) -> Void) {
        completion(context.isPreview ? .placeholder : read())
    }

    func getTimeline(in context: Context,
                     completion: @escaping (Timeline<LastClassificationEntry>) -> Void) {
        // The watch app reloads the timeline when a result arrives, so there is
        // nothing to poll for and no reason to schedule a refresh.
        completion(Timeline(entries: [read()], policy: .never))
    }

    private func read() -> LastClassificationEntry {
        guard let defaults = UserDefaults(suiteName: Self.suite),
              let data = defaults.data(forKey: "lastResult"),
              let stored = try? JSONDecoder().decode(StoredResult.self, from: data)
        else { return .empty }

        return LastClassificationEntry(
            date: stored.receivedAt,
            family: stored.family,
            accession: stored.accession,
            probability: stored.probability,
            band: stored.band,
            isPlaceholder: false
        )
    }

    private struct StoredResult: Codable {
        let family: String
        let accession: String
        let clan: String?
        let probability: Double
        let band: String
        let residueCount: Int
        let receivedAt: Date
    }
}

struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: LastClassificationEntry

    private var tint: Color {
        switch entry.band {
        case "high": return Color(red: 0.37, green: 0.92, blue: 0.83)
        case "mid": return Color(red: 0.98, green: 0.75, blue: 0.14)
        case "low": return Color(red: 0.98, green: 0.45, blue: 0.52)
        default: return .secondary
        }
    }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(max(entry.probability, 0), 1)) {
                Image(systemName: "sparkles")
            } currentValueLabel: {
                Text(entry.probability, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.body, design: .rounded, weight: .semibold))
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tint)

        case .accessoryCorner:
            Image(systemName: "sparkles")
                .font(.title)
                .widgetLabel {
                    Text(entry.family)
                }

        case .accessoryInline:
            // One line, so it has to carry the family rather than the number:
            // a bare percentage on a watch face means nothing on its own.
            Text("\(entry.family) \(entry.probability, format: .percent.precision(.fractionLength(0)))")

        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.family)
                    .font(.system(.headline, design: .rounded))
                    .lineLimit(1)
                if !entry.accession.isEmpty {
                    Text(entry.accession)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Gauge(value: min(max(entry.probability, 0), 1)) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(tint)
            }
        }
    }
}
