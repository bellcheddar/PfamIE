import SwiftUI
// The watch companion shares the engine, the models and the theme, but none of
// the phone and desktop UI: it carries no assets and shows one glance view.
// SwiftUI on watchOS also lacks TextEditor, fileImporter, textSelection,
// segmented pickers and keyboard shortcuts, so compiling these views there
// fails on about a dozen counts. Excluding them is the honest description of
// the architecture as well as the fix, and it keeps the watch binary small.
#if !os(watchOS)

/// How domains are put together: what travels with what, in what order, and
/// what else is built the same way.
public struct GrammarianView: View {
    @Environment(\.theme) private var theme
    @Environment(AppEnvironment.self) private var app
    @Environment(Router.self) private var router

    @State private var focus: Family?
    @State private var architectures: [Architecture] = []
    @State private var partners: [Partner] = []
    @State private var loading = false
    @State private var query = ""

    struct Partner: Identifiable {
        let family: Family
        let edge: CooccurrenceEdge
        var id: PfamID { family.accession }
    }

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let focus {
                    focusHeader(focus)
                    if loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else {
                        if !partners.isEmpty { partnerSection(focus) }
                        if !architectures.isEmpty { architectureSection(focus) }
                        if partners.isEmpty && architectures.isEmpty {
                            Text("\(focus.displayName) is not recorded alongside other Pfam domains "
                                 + "in any sampled architecture. Plenty of families travel alone.")
                                .font(.callout)
                                .foregroundStyle(theme.inkSecondary)
                        }
                    }
                } else {
                    emptyState
                }
            }
            .padding(20)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bgDeep)
        .navigationTitle(AppTab.grammarian.title)
        .searchable(text: $query, prompt: "Find a family")
        .onSubmit(of: .search) { Task { await resolve(query) } }
        .task(id: router.grammarianArchitecture) { await loadRequested() }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 34))
                .foregroundStyle(theme.accentPulsar.opacity(0.7))
            Text("Pick a domain and see what it travels with")
                .font(.headline)
            Text("Classify a sequence in the Oracle, or search for a family above.")
                .font(.footnote)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
            Button("Open the Oracle", systemImage: "wand.and.stars") {
                router.go(.oracle(prefill: nil))
            }
            .buttonStyle(.bordered)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }

    private func focusHeader(_ family: Family) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                FamilyChip(family: family, showsAccession: true,
                           tint: app.clanColour(for: family, theme: theme))
                Spacer()
            }
            Text(family.summary)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(family.architectureCount.formatted()) distinct domain architectures contain it.")
                .font(.caption).foregroundStyle(theme.inkSecondary)
        }
    }

    private func partnerSection(_ family: Family) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Travels with").font(.headline)
            CooccurrenceGraph(
                centre: family,
                partners: partners,
                colourFor: { app.clanColour(for: $0, theme: theme) }
            )
            VStack(spacing: 8) {
                ForEach(partners.prefix(10)) { partner in
                    orderRow(family: family, partner: partner)
                }
            }
        }
    }

    /// "SH3_1, always N-terminal" or "PH, N-terminal in 76%".
    private func orderRow(family: Family, partner: Partner) -> some View {
        HStack(spacing: 10) {
            FamilyChip(family: partner.family,
                       tint: app.clanColour(for: partner.family, theme: theme))
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(partner.edge.proteinCount.formatted(.number.notation(.compactName))) proteins")
                    .font(.caption).monospacedDigit()
                Text(orderingText(partner))
                    .font(.caption2)
                    .foregroundStyle(orderingColour(partner))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline))
    }

    private func orderingText(_ partner: Partner) -> String {
        let name = partner.family.displayName
        switch partner.edge.ordering {
        case .alwaysBefore:
            return "\(name) always N-terminal"
        case .alwaysAfter:
            return "\(name) always C-terminal"
        case .mostlyBefore(let fraction):
            return "\(name) N-terminal in \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        case .mostlyAfter(let fraction):
            return "\(name) C-terminal in \(fraction.formatted(.percent.precision(.fractionLength(0))))"
        case .tooFewToSay:
            // Below ten shared proteins an ordering claim is noise.
            return "too few to call an order"
        }
    }

    /// The pairs that vary are the interesting ones, so they are the ones
    /// picked out rather than the invariant majority.
    private func orderingColour(_ partner: Partner) -> Color {
        switch partner.edge.ordering {
        case .mostlyBefore, .mostlyAfter: return theme.accentFlare
        default: return theme.inkSecondary
        }
    }

    private func architectureSection(_ family: Family) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Built like this").font(.headline)
            ForEach(architectures.prefix(10)) { architecture in
                ArchitectureRow(architecture: architecture, home: family.accession)
            }
        }
    }

    // MARK: - Loading

    private func loadRequested() async {
        let requested = router.grammarianArchitecture
        guard !requested.isEmpty else { return }
        if requested.count == 1 {
            await load(app.family(requested[0]))
        } else {
            await loadArchitecture(requested)
        }
    }

    private func resolve(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let engine = app.engine else { return }
        let hits = (try? await engine.store.search(text: trimmed, limit: 1)) ?? []
        await load(hits.first)
    }

    private func load(_ family: Family?) async {
        focus = family
        guard let family, let engine = app.engine else { return }
        loading = true
        defer { loading = false }

        architectures = (try? await engine.store.architectures(forFamilyRow: family.row)) ?? []
        let edges = (try? await engine.store.cooccurrence(forFamilyRow: family.row)) ?? []
        let families = (try? await engine.store.families(rows: edges.map(\.partnerRow))) ?? []
        let byRow = Dictionary(uniqueKeysWithValues: families.map { ($0.row, $0) })
        partners = edges.compactMap { edge in
            byRow[edge.partnerRow].map { Partner(family: $0, edge: edge) }
        }
    }

    /// "What else is built like mine": every architecture containing all of the
    /// domains the Oracle called, commonest first.
    private func loadArchitecture(_ members: [PfamID]) async {
        guard let engine = app.engine else { return }
        loading = true
        defer { loading = false }
        focus = app.family(members[0])
        architectures = (try? await engine.store.architectures(containing: members)) ?? []
        if let first = focus {
            let edges = (try? await engine.store.cooccurrence(forFamilyRow: first.row)) ?? []
            let families = (try? await engine.store.families(rows: edges.map(\.partnerRow))) ?? []
            let byRow = Dictionary(uniqueKeysWithValues: families.map { ($0.row, $0) })
            partners = edges.compactMap { edge in
                byRow[edge.partnerRow].map { Partner(family: $0, edge: edge) }
            }
        }
    }
}

/// A radial co-occurrence graph, drawn with Canvas.
///
/// Edge thickness is the log of the shared protein count: linear thickness
/// makes one huge partner the only visible edge, which is a picture of one fact
/// rather than of a neighbourhood.
struct CooccurrenceGraph: View {
    @Environment(\.theme) private var theme
    @Environment(Router.self) private var router

    let centre: Family
    let partners: [GrammarianView.Partner]
    let colourFor: (Family) -> Color

    private var shown: [GrammarianView.Partner] { Array(partners.prefix(12)) }

    var body: some View {
        GeometryReader { geometry in
            let size = min(geometry.size.width, 260)
            let mid = CGPoint(x: geometry.size.width / 2, y: size / 2)
            let radius = size * 0.38
            let maximum = Double(shown.map(\.edge.proteinCount).max() ?? 1)

            ZStack {
                Canvas { context, _ in
                    for (index, partner) in shown.enumerated() {
                        let angle = Double(index) / Double(max(shown.count, 1)) * 2 * .pi - .pi / 2
                        let point = CGPoint(
                            x: mid.x + cos(angle) * radius,
                            y: mid.y + sin(angle) * radius
                        )
                        var path = Path()
                        path.move(to: mid)
                        path.addLine(to: point)
                        let weight = log10(Double(partner.edge.proteinCount) + 1)
                            / log10(maximum + 1)
                        context.stroke(
                            path,
                            with: .color(colourFor(partner.family).opacity(0.22 + weight * 0.5)),
                            lineWidth: 0.8 + weight * 3.4
                        )
                    }
                }

                ForEach(Array(shown.enumerated()), id: \.element.id) { index, partner in
                    let angle = Double(index) / Double(max(shown.count, 1)) * 2 * .pi - .pi / 2
                    Button {
                        router.go(.grammarian(architecture: [partner.family.accession]))
                    } label: {
                        Text(partner.family.displayName)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(theme.bgRaised, in: Capsule())
                            .overlay(Capsule().strokeBorder(colourFor(partner.family).opacity(0.6)))
                    }
                    .buttonStyle(.plain)
                    .position(x: mid.x + cos(angle) * radius, y: mid.y + sin(angle) * radius)
                }

                Text(centre.displayName)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(theme.accentFlare.opacity(0.2), in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.accentFlare.opacity(0.8)))
                    .position(mid)
            }
        }
        .frame(height: 270)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(centre.displayName) co-occurs with \(shown.count) other families")
    }
}

#endif
