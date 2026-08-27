import SwiftUI
// The watch companion shares the engine, the models and the theme, but none of
// the phone and desktop UI: it carries no assets and shows one glance view.
// SwiftUI on watchOS also lacks TextEditor, fileImporter, textSelection,
// segmented pickers and keyboard shortcuts, so compiling these views there
// fails on about a dozen counts. Excluding them is the honest description of
// the architecture as well as the fix, and it keeps the watch binary small.
#if !os(watchOS)

/// The universal family card, presented as a sheet from anywhere in the app.
///
/// Every route into a family ends here, so this is the one place that has to
/// carry all of it: what the family is, who its clan siblings are, how it is
/// usually built into proteins, and a way through to the structure, the Galaxy
/// and the Oracle. A card that dead-ends is a tab that dead-ends.
public struct FamilyCard: View {
    @Environment(\.theme) private var theme
    @Environment(AppEnvironment.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    private let accession: PfamID

    @State private var family: Family?
    @State private var siblings: [Family] = []
    @State private var architectures: [Architecture] = []
    @State private var neighbours: [PfamIEEngine.Hypothesis] = []
    @State private var loaded = false

    public init(accession: PfamID) { self.accession = accession }

    public var body: some View {
        NavigationStack {
            ScrollView {
                if let family {
                    content(family)
                } else if loaded {
                    ContentUnavailableView(
                        "Family not found",
                        systemImage: "questionmark.folder",
                        description: Text("\(accession.rawValue) is not in this Pfam release.")
                    )
                    .padding(.top, 60)
                } else {
                    ProgressView().padding(.top, 80)
                }
            }
            .background(theme.bgDeep)
            .navigationTitle(family?.displayName ?? accession.rawValue)
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task(id: accession) { await load() }
    }

    @ViewBuilder
    private func content(_ family: Family) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            header(family)

            if !family.abstract.isEmpty {
                Text(family.abstract)
                    .font(.callout)
                    .foregroundStyle(theme.inkPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            } else if !family.summary.isEmpty {
                Text(family.summary).font(.callout)
            }

            statsGrid(family)

            if let representative = family.representative {
                StructurePeek(
                    uniprot: representative.uniprot,
                    highlight: representative.range,
                    caption: "AlphaFold model of \(representative.uniprot), "
                        + "residues \(representative.start) to \(representative.end)"
                )
            }

            if !architectures.isEmpty {
                section("Usually built like this") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(architectures.prefix(6)) { architecture in
                            ArchitectureRow(architecture: architecture, home: family.accession)
                        }
                    }
                }
            }

            if family.isDUF && !neighbours.isEmpty {
                section("Nearest annotated families") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("These are the closest families in embedding space that do have a function. They are leads, not annotations.")
                            .font(.caption)
                            .foregroundStyle(theme.inkSecondary)
                        FlowRow(spacing: 8) {
                            ForEach(neighbours.prefix(8)) { hypothesis in
                                FamilyChip(
                                    family: hypothesis.neighbour,
                                    tint: app.clanColour(for: hypothesis.neighbour, theme: theme)
                                )
                            }
                        }
                    }
                }
            }

            if !siblings.isEmpty {
                section("Clan siblings") {
                    FlowRow(spacing: 8) {
                        ForEach(siblings.prefix(24)) { sibling in
                            FamilyChip(family: sibling,
                                       tint: app.clanColour(for: sibling, theme: theme))
                        }
                    }
                }
            }

            actions(family)
        }
        .padding(20)
        .frame(maxWidth: 720, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func header(_ family: Family) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(family.accession.rawValue)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(theme.inkSecondary)
                    .textSelection(.enabled)
                Text(family.type.rawValue)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(theme.inkSecondary.opacity(0.15), in: Capsule())
                if family.isDUF {
                    Text("Unknown function")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(theme.accentFlare.opacity(0.18), in: Capsule())
                        .foregroundStyle(theme.accentFlare)
                }
            }
            Text(family.summary)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)

            if let clan = family.clan, let record = app.clanByAccession[clan] {
                Button {
                    router.go(.galaxy(focus: family.accession))
                } label: {
                    Label(
                        "\(record.identifier ?? clan.rawValue) \u{00B7} \(record.familyCount) families",
                        systemImage: "circle.hexagongrid.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(theme.accentPulsar)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statsGrid(_ family: Family) -> some View {
        FlowRow(spacing: 10) {
            stat("Proteins", family.proteinCount.formatted(.number.notation(.compactName)))
            stat("Species", family.taxonCount.formatted(.number.notation(.compactName)))
            stat("Structures", family.structureCount.formatted())
            stat("Architectures", family.architectureCount.formatted(.number.notation(.compactName)))
            stat("Seed", "\(family.seedCount) sequences")
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .monospacedDigit()
            Text(label).font(.caption2).foregroundStyle(theme.inkSecondary)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.hairline))
    }

    private func actions(_ family: Family) -> some View {
        FlowRow(spacing: 10) {
            Button("Show in Galaxy", systemImage: "sparkles") {
                dismiss(); router.go(.galaxy(focus: family.accession))
            }
            Button("Similar architectures", systemImage: "puzzlepiece.extension") {
                dismiss(); router.go(.grammarian(architecture: [family.accession]))
            }
            if let representative = family.representative {
                Button("Open structure", systemImage: "cube.transparent") {
                    router.go(.structure(uniprot: representative.uniprot,
                                         highlight: representative.range))
                }
            }
        }
        .buttonStyle(.bordered)
        .font(.footnote)
    }

    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
    }

    private func load() async {
        loaded = false
        guard let engine = app.engine else { loaded = true; return }
        let found = app.family(accession)
        family = found
        guard let found else { loaded = true; return }

        async let siblingTask = (try? await engine.store.families(inClan: found.clan ?? ClanID(""))) ?? []
        async let architectureTask = (try? await engine.store.architectures(forFamilyRow: found.row)) ?? []
        let hypothesisTask: [PfamIEEngine.Hypothesis] = found.isDUF
            ? ((try? await engine.hypotheses(for: found)) ?? [])
            : []

        siblings = (await siblingTask).filter { $0.accession != accession }
        architectures = await architectureTask
        neighbours = hypothesisTask
        loaded = true
    }
}

/// One architecture, drawn as its ordered chips.
struct ArchitectureRow: View {
    @Environment(\.theme) private var theme
    @Environment(AppEnvironment.self) private var app
    @Environment(Router.self) private var router

    let architecture: Architecture
    let home: PfamID?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowRow(spacing: 6) {
                ForEach(Array(architecture.members.enumerated()), id: \.offset) { index, member in
                    if index > 0 {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(theme.inkSecondary)
                    }
                    if let family = app.family(member) {
                        FamilyChip(
                            family: family,
                            tint: member == home
                                ? theme.accentFlare
                                : app.clanColour(for: family, theme: theme)
                        )
                    } else {
                        Text(member.rawValue)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(theme.inkSecondary)
                    }
                }
            }
            Text("\(architecture.proteinCount.formatted(.number.notation(.compactName))) proteins")
                .font(.caption2)
                .foregroundStyle(theme.inkSecondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(theme.hairline))
        .contextMenu {
            Button("Explore this architecture", systemImage: "puzzlepiece.extension") {
                router.go(.grammarian(architecture: architecture.members))
            }
            if let uniprot = architecture.representativeUniProt {
                Button("View a protein built this way", systemImage: "cube.transparent") {
                    router.go(.structure(uniprot: uniprot, highlight: nil))
                }
            }
        }
    }
}

#endif
