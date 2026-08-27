import SwiftUI

/// The landing page: every Pfam family as a point, clans as coloured regions,
/// and the last classified sequence as an amber comet.
public struct GalaxyView: View {
    @Environment(\.theme) private var theme
    @Environment(AppEnvironment.self) private var app
    @Environment(Router.self) private var router
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model = GalaxyModel()
    @State private var focusRow: Int?
    @State private var selection: Family?
    @State private var query = ""
    @State private var showingLegend = false
    @State private var built = false

    public init() {}

    public var body: some View {
        ZStack(alignment: .top) {
            theme.bgDeep.ignoresSafeArea()

            #if canImport(SceneKit) && !os(visionOS) && !os(watchOS)
            SceneKitGalaxy(
                points: model.points,
                theme: theme,
                focusRow: focusRow,
                cometPosition: model.cometPosition,
                onSelect: { index in
                    guard let family = app.family(row: model.points[index].row) else { return }
                    selection = family
                }
            )
            .ignoresSafeArea()
            #else
            GalaxyFallback(points: model.points, theme: theme)
                .ignoresSafeArea()
            #endif

            VStack(spacing: 0) {
                searchBar
                Spacer()
                if let selection { selectionChip(selection) }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 14)
        }
        .navigationTitle(AppTab.galaxy.title)
        #if !os(macOS)
        .toolbarVisibility(.hidden, for: .navigationBar)
        #endif
        .sheet(isPresented: $showingLegend) { clanLegend }
        .task {
            guard !built else { return }
            model.build(from: app, theme: theme)
            built = true
        }
        .onChange(of: app.lastClassification?.residueCount) { _, _ in placeComet() }
        .onAppear { consumeFocus() }
        .onChange(of: router.galaxyFocus) { _, _ in consumeFocus() }
        .sensoryFeedback(.selection, trigger: selection?.row)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(theme.inkSecondary)
            TextField("Fly to a family", text: $query)
                .textFieldStyle(.plain)
                .font(.system(.subheadline, design: .rounded))
                .onSubmit { Task { await flyToNamed() } }
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkSecondary)
            }

            Divider().frame(height: 18)

            Button { showingLegend = true } label: {
                Image(systemName: "circle.hexagongrid.fill")
                    .foregroundStyle(theme.accentPulsar)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clan legend")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(theme.hairline))
        .padding(.top, 8)
    }

    private func selectionChip(_ family: Family) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(app.clanColour(for: family, theme: theme))
                    .frame(width: 10, height: 10)
                Text(family.displayName)
                    .font(.system(.headline, design: .rounded))
                Spacer()
                Button {
                    selection = nil
                } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.inkSecondary)
            }
            Text(family.summary)
                .font(.caption)
                .foregroundStyle(theme.inkSecondary)
                .lineLimit(2)
            HStack(spacing: 8) {
                Button("Open card") { router.go(.family(family.accession)) }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accentNova)
                Button("Scan against it") {
                    router.go(.oracle(prefill: nil))
                }
                .buttonStyle(.bordered)
            }
            .font(.footnote)
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.hairline))
        .frame(maxWidth: 420)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(reduceMotion ? nil : .snappy, value: family.row)
        .contextMenu { FamilyActions(family: family) }
    }

    private var clanLegend: some View {
        NavigationStack {
            List(app.clans) { clan in
                Button {
                    showingLegend = false
                    if let first = app.families.first(where: { $0.clan == clan.accession }) {
                        focusRow = first.row
                    }
                } label: {
                    HStack {
                        Circle()
                            .fill(theme.clanColour(hue: clan.hue))
                            .frame(width: 12, height: 12)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clan.identifier ?? clan.accession.rawValue)
                                .font(.system(.subheadline, design: .rounded, weight: .medium))
                            if let summary = clan.summary {
                                Text(summary).font(.caption)
                                    .foregroundStyle(theme.inkSecondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("\(clan.familyCount)")
                            .font(.system(.caption, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(theme.inkSecondary)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(theme.bgRaised)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(theme.bgDeep)
            .navigationTitle("\(app.clans.count) clans")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { showingLegend = false }
                }
            }
        }
    }

    private func consumeFocus() {
        guard let accession = router.consumeGalaxyFocus(),
              let family = app.family(accession) else { return }
        focusRow = family.row
        selection = family
    }

    private func flyToNamed() async {
        guard let engine = app.engine else { return }
        let hits = (try? await engine.store.search(text: query, limit: 1)) ?? []
        guard let family = hits.first else { return }
        focusRow = family.row
        selection = family
    }

    /// Drop the Oracle's result into the map among the families it resembles.
    private func placeComet() {
        guard let classification = app.lastClassification else {
            model.cometPosition = nil
            return
        }
        let neighbours = classification.hits.map {
            CentroidIndex.Neighbour(row: $0.family.row,
                                    similarity: $0.similarity,
                                    probability: $0.probability)
        }
        model.cometPosition = model.cometPosition(
            for: neighbours,
            families: classification.hits.map(\.family)
        )
    }
}

/// The 2D map, for platforms without SceneKit and as the honest fallback if
/// the 3D view ever cannot be drawn. Same data, same taps.
struct GalaxyFallback: View {
    let points: [GalaxyModel.Point]
    let theme: Theme

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width, size.height) * 0.45
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            for point in points {
                let x = centre.x + CGFloat(point.position.x) * scale
                let y = centre.y + CGFloat(point.position.y) * scale
                let radius = CGFloat(point.radius) * 0.45
                let rect = CGRect(x: x - radius, y: y - radius,
                                  width: radius * 2, height: radius * 2)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .color(Color(
                        red: Double(point.colour.x),
                        green: Double(point.colour.y),
                        blue: Double(point.colour.z)
                    ).opacity(point.isDUF ? 0.35 : 0.85))
                )
            }
        }
        .background(theme.bgDeep)
    }
}
