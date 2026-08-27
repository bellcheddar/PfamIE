import SwiftUI
// The watch companion shares the engine, the models and the theme, but none of
// the phone and desktop UI: it carries no assets and shows one glance view.
// SwiftUI on watchOS also lacks TextEditor, fileImporter, textSelection,
// segmented pickers and keyboard shortcuts, so compiling these views there
// fails on about a dozen counts. Excluding them is the honest description of
// the architecture as well as the fix, and it keeps the watch binary small.
#if !os(watchOS)

/// The dark proteome: 7,874 families with no known function, and the nearest
/// annotated family to each.
///
/// The wording throughout is deliberately hypothesis-flavoured. Nearest
/// neighbour in an embedding space is a lead worth following, not an
/// annotation, and a tool that blurs the two is worse than no tool.
public struct ProspectorView: View {
    @Environment(\.theme) private var theme
    @Environment(AppEnvironment.self) private var app
    @Environment(Router.self) private var router

    public enum SortOrder: String, CaseIterable, Identifiable {
        case size, breadth, accession
        public var id: String { rawValue }
        var title: String {
            switch self {
            case .size: return "Most proteins"
            case .breadth: return "Most species"
            case .accession: return "Accession"
            }
        }
    }

    @State private var order: SortOrder = .size
    @State private var selected: Family?
    @State private var hypotheses: [PfamIEEngine.Hypothesis] = []
    @State private var loadingHypotheses = false
    @State private var filter = ""

    public init() {}

    private var dufs: [Family] {
        let all = app.families.filter(\.isDUF)
        let matched = filter.isEmpty ? all : all.filter {
            $0.identifier.localizedCaseInsensitiveContains(filter)
                || $0.accession.rawValue.localizedCaseInsensitiveContains(filter)
                || $0.summary.localizedCaseInsensitiveContains(filter)
        }
        switch order {
        case .size: return matched.sorted { $0.proteinCount > $1.proteinCount }
        case .breadth: return matched.sorted { $0.taxonCount > $1.taxonCount }
        case .accession: return matched.sorted { $0.accession < $1.accession }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            List {
                ForEach(dufs.prefix(400)) { family in
                    Button { select(family) } label: { row(family) }
                        .buttonStyle(.plain)
                        .listRowBackground(theme.bgRaised)
                        .contextMenu { FamilyActions(family: family) }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(theme.bgDeep)
        .navigationTitle(AppTab.prospector.title)
        .searchable(text: $filter, prompt: "Filter unknown families")
        .sheet(item: $selected) { family in
            hypothesisSheet(family)
        }
        .onAppear {
            if let requested = router.presentedFamily,
               let family = app.family(requested), family.isDUF {
                select(family)
                router.presentedFamily = nil
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(app.families.count(where: \.isDUF).formatted()) families have no assigned function. "
                 + "That is \(percentUnknown) of Pfam.")
                .font(.footnote)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Picker("Sort", selection: $order) {
                ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(theme.bgDeep)
    }

    private var percentUnknown: String {
        guard !app.families.isEmpty else { return "0%" }
        let fraction = Double(app.families.count(where: \.isDUF)) / Double(app.families.count)
        return fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    private func row(_ family: Family) -> some View {
        HStack(spacing: 10) {
            // DUFs render hollow here and in the Galaxy: the same visual
            // language for "we do not know what this is" in both places.
            Circle()
                .strokeBorder(theme.accentFlare.opacity(0.8), lineWidth: 1.5)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(family.displayName)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                Text(family.summary).font(.caption)
                    .foregroundStyle(theme.inkSecondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 1) {
                Text(family.proteinCount.formatted(.number.notation(.compactName)))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                Text("\(family.taxonCount.formatted(.number.notation(.compactName))) species")
                    .font(.caption2).foregroundStyle(theme.inkSecondary)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func hypothesisSheet(_ family: Family) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(family.summary)
                            .font(.system(.title3, design: .rounded, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(family.accession.rawValue) \u{00B7} "
                             + "\(family.proteinCount.formatted()) proteins across "
                             + "\(family.taxonCount.formatted()) species")
                            .font(.caption).foregroundStyle(theme.inkSecondary)
                    }

                    if loadingHypotheses {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if hypotheses.isEmpty {
                        Text("No annotated family sits close enough to this one to suggest anything.")
                            .font(.callout).foregroundStyle(theme.inkSecondary)
                    } else {
                        Text(leadSentence(family))
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 8) {
                            ForEach(hypotheses) { hypothesis in
                                hypothesisRow(hypothesis)
                            }
                        }

                        Text("These are the nearest families in embedding space. Proximity is a "
                             + "reason to look, not evidence of function: the Oracle is right "
                             + "about half the time on real proteins, and this is a weaker claim "
                             + "than that.")
                            .font(.caption)
                            .foregroundStyle(theme.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let representative = family.representative {
                        StructurePeek(
                            uniprot: representative.uniprot,
                            highlight: representative.range,
                            caption: "AlphaFold covers most unknown families. The fold is often the "
                                + "first real clue."
                        )
                    }
                }
                .padding(20)
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(theme.bgDeep)
            .navigationTitle(family.displayName)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { selected = nil }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Show in Galaxy", systemImage: "sparkles") {
                        selected = nil
                        router.go(.galaxy(focus: family.accession))
                    }
                }
            }
        }
    }

    private func hypothesisRow(_ hypothesis: PfamIEEngine.Hypothesis) -> some View {
        Button {
            router.go(.family(hypothesis.neighbour.accession))
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(app.clanColour(for: hypothesis.neighbour, theme: theme))
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hypothesis.neighbour.displayName)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                    Text(hypothesis.neighbour.summary)
                        .font(.caption).foregroundStyle(theme.inkSecondary).lineLimit(2)
                }
                Spacer(minLength: 6)
                Text(hypothesis.similarity, format: .number.precision(.fractionLength(2)))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(theme.inkSecondary)
                    .monospacedDigit()
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.hairline))
        }
        .buttonStyle(.plain)
        .contextMenu { FamilyActions(family: hypothesis.neighbour) }
    }

    /// "DUF4784 sits nearest to Glyco_hydro families: candidate
    /// carbohydrate-active?" phrased from whatever the neighbours actually are.
    private func leadSentence(_ family: Family) -> String {
        let names = hypotheses.prefix(3).map(\.neighbour.displayName)
        guard let first = names.first else { return "" }
        let rest = names.dropFirst()
        let list = rest.isEmpty
            ? first
            : ([first] + rest).joined(separator: ", ")
        return "\(family.displayName) sits nearest to \(list). Worth asking whether it shares "
            + "their chemistry."
    }

    private func select(_ family: Family) {
        selected = family
        hypotheses = []
        loadingHypotheses = true
        Task {
            guard let engine = app.engine else { loadingHypotheses = false; return }
            hypotheses = (try? await engine.hypotheses(for: family)) ?? []
            loadingHypotheses = false
        }
    }
}

#endif
