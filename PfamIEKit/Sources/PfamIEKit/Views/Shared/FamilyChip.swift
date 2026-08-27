import SwiftUI
// The watch companion shares the engine, the models and the theme, but none of
// the phone and desktop UI: it carries no assets and shows one glance view.
// SwiftUI on watchOS also lacks TextEditor, fileImporter, textSelection,
// segmented pickers and keyboard shortcuts, so compiling these views there
// fails on about a dozen counts. Excluding them is the honest description of
// the architecture as well as the fix, and it keeps the watch binary small.
#if !os(watchOS)

/// A family, rendered small, with the universal context menu attached.
///
/// This is the connective tissue: the same four actions on every family
/// reference anywhere in the app, so no chip is ever a dead end. If a new
/// place shows a family, it shows this, and the navigation comes free.
public struct FamilyChip: View {
    @Environment(\.theme) private var theme
    @Environment(Router.self) private var router

    private let family: Family
    private let showsAccession: Bool
    private let tint: Color?

    public init(family: Family, showsAccession: Bool = false, tint: Color? = nil) {
        self.family = family
        self.showsAccession = showsAccession
        self.tint = tint
    }

    private var colour: Color { tint ?? theme.accentNova }

    public var body: some View {
        Button {
            router.go(.family(family.accession))
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(colour)
                    .frame(width: 7, height: 7)
                Text(family.displayName)
                    .font(.system(.subheadline, design: .rounded, weight: .medium))
                if showsAccession {
                    Text(family.accession.rawValue)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(theme.inkSecondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(colour.opacity(0.12), in: Capsule())
            .overlay(Capsule().strokeBorder(colour.opacity(0.35), lineWidth: 0.5))
            .foregroundStyle(theme.inkPrimary)
        }
        .buttonStyle(.plain)
        .contextMenu { FamilyActions(family: family) }
        .accessibilityLabel("\(family.displayName), \(family.accession.rawValue)")
        .accessibilityHint("Opens the family card")
    }
}

/// The four things you can always do with a family.
public struct FamilyActions: View {
    @Environment(Router.self) private var router
    private let family: Family

    public init(family: Family) { self.family = family }

    public var body: some View {
        Button("Open card", systemImage: "rectangle.portrait.and.arrow.right") {
            router.go(.family(family.accession))
        }
        Button("Show in Galaxy", systemImage: "sparkles") {
            router.go(.galaxy(focus: family.accession))
        }
        Button("Similar architectures", systemImage: "puzzlepiece.extension") {
            router.go(.grammarian(architecture: [family.accession]))
        }
        if let representative = family.representative {
            Button("View structure", systemImage: "cube.transparent") {
                router.go(.structure(uniprot: representative.uniprot,
                                     highlight: representative.range))
            }
        }
        if family.isDUF {
            Divider()
            Button("Function hypotheses", systemImage: "questionmark.diamond") {
                router.go(.prospector(duf: family.accession))
            }
        }
    }
}

#endif
