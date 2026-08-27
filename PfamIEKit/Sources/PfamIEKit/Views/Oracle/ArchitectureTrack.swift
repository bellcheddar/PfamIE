import SwiftUI
// The watch companion shares the engine, the models and the theme, but none of
// the phone and desktop UI: it carries no assets and shows one glance view.
// SwiftUI on watchOS also lacks TextEditor, fileImporter, textSelection,
// segmented pickers and keyboard shortcuts, so compiling these views there
// fails on about a dozen counts. Excluding them is the honest description of
// the architecture as well as the fix, and it keeps the watch binary small.
#if !os(watchOS)

/// The N-to-C domain architecture of a scanned sequence, drawn to scale.
///
/// A ruler with a lozenge per called domain. Positions are residue numbers in
/// the sanitised sequence, so they line up with what the user pasted rather
/// than with some internal padded coordinate.
public struct ArchitectureTrack: View {
    @Environment(\.theme) private var theme
    @Environment(Router.self) private var router

    private let residueCount: Int
    private let domains: [PfamIEEngine.Classification.Domain]

    public init(
        residueCount: Int,
        domains: [PfamIEEngine.Classification.Domain]
    ) {
        self.residueCount = residueCount
        self.domains = domains
    }

    private func colour(for domain: PfamIEEngine.Classification.Domain) -> Color {
        let index = domains.firstIndex(where: { $0.id == domain.id }) ?? 0
        return theme.domainColour(at: index)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let scale = width / CGFloat(max(residueCount, 1))

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.inkSecondary.opacity(0.18))
                        .frame(height: 10)

                    ForEach(domains) { domain in
                        let tint = colour(for: domain)
                        let x = CGFloat(domain.start - 1) * scale
                        let w = max(CGFloat(domain.length) * scale, 3)
                        Button {
                            router.go(.family(domain.family.accession))
                        } label: {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(tint.gradient)
                                .frame(width: w, height: 26)
                                .overlay(
                                    Text(domain.family.displayName)
                                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                        .padding(.horizontal, 4)
                                        .opacity(w > 46 ? 1 : 0)
                                )
                                .shadow(color: tint.opacity(theme.isDark ? 0.5 : 0.2),
                                        radius: 5)
                        }
                        .buttonStyle(.plain)
                        .offset(x: x)
                        .contextMenu { FamilyActions(family: domain.family) }
                        .accessibilityLabel(
                            "\(domain.family.displayName), residues \(domain.start) to \(domain.end)"
                        )
                    }
                }
                .frame(height: 30)
            }
            .frame(height: 30)

            HStack {
                Text("1")
                Spacer()
                Text("\(residueCount)")
            }
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(theme.inkSecondary)

            if domains.isEmpty {
                Text("No domain reached the confidence threshold along this sequence.")
                    .font(.footnote)
                    .foregroundStyle(theme.inkSecondary)
            } else {
                Text(summary)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(theme.inkSecondary)
                    .textSelection(.enabled)
            }
        }
    }

    /// "SH3 (86-245) -> SH2 (246-365) -> PK_Tyr_Ser-Thr (366-525)", N to C.
    private var summary: String {
        domains
            .map { "\($0.family.displayName) (\($0.start)-\($0.end))" }
            .joined(separator: " \u{2192} ")
    }
}

#endif
