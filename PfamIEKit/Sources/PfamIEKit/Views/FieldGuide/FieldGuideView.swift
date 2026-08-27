import SwiftUI
// The watch companion shares the engine, the models and the theme, but none of
// the phone and desktop UI: it carries no assets and shows one glance view.
// SwiftUI on watchOS also lacks TextEditor, fileImporter, textSelection,
// segmented pickers and keyboard shortcuts, so compiling these views there
// fails on about a dozen counts. Excluding them is the honest description of
// the architecture as well as the fix, and it keeps the watch binary small.
#if !os(watchOS)

/// The offline Pfam atlas, searched in plain language.
public struct FieldGuideView: View {
    @Environment(\.theme) private var theme
    @Environment(AppEnvironment.self) private var app
    @Environment(Router.self) private var router

    @State private var query = ""
    @State private var results: [PfamIEEngine.SearchResult] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    private static let suggestions = [
        "breaks down plastic",
        "haem-binding families that dimerise",
        "zinc finger",
        "moves protons across a membrane",
        "cuts double-stranded DNA",
    ]

    public init() {}

    public var body: some View {
        List {
            if query.isEmpty {
                browseSection
            } else if results.isEmpty && !isSearching {
                Section {
                    ContentUnavailableView.search(text: query)
                }
            } else {
                Section {
                    ForEach(results) { result in
                        resultRow(result)
                    }
                } header: {
                    HStack {
                        Text("\(results.count) families")
                        if isSearching {
                            Spacer()
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.bgDeep)
        .navigationTitle(AppTab.fieldGuide.title)
        .searchable(text: $query, prompt: "Describe a family, or name one")
        .onChange(of: query) { _, new in scheduleSearch(new) }
        .onAppear {
            if let incoming = router.fieldGuideQuery {
                query = incoming
                router.fieldGuideQuery = nil
            }
        }
    }

    private var browseSection: some View {
        Group {
            Section("Try asking for") {
                ForEach(Self.suggestions, id: \.self) { suggestion in
                    Button {
                        query = suggestion
                    } label: {
                        Label(suggestion, systemImage: "sparkle.magnifyingglass")
                            .font(.subheadline)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listRowBackground(theme.bgRaised)

            Section("Largest clans") {
                ForEach(app.clans.prefix(30)) { clan in
                    NavigationLink(value: clan.accession) {
                        HStack {
                            Circle()
                                .fill(theme.clanColour(hue: clan.hue))
                                .frame(width: 10, height: 10)
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
                                .foregroundStyle(theme.inkSecondary)
                                .monospacedDigit()
                        }
                    }
                }
            }
            .listRowBackground(theme.bgRaised)
        }
    }

    private func resultRow(_ result: PfamIEEngine.SearchResult) -> some View {
        Button {
            router.go(.family(result.family.accession))
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(app.clanColour(for: result.family, theme: theme))
                    .frame(width: 9, height: 9)
                    .padding(.top, 5)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(result.family.displayName)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                        Text(result.family.accession.rawValue)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(theme.inkSecondary)
                        if result.family.isDUF {
                            Text("DUF")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(theme.accentFlare.opacity(0.2), in: Capsule())
                                .foregroundStyle(theme.accentFlare)
                        }
                    }
                    Text(result.family.summary)
                        .font(.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 4)
                // Say which search found it: a literal name match and a
                // description that merely reads similarly are different claims.
                Image(systemName: result.literal ? "textformat.abc" : "brain")
                    .font(.caption2)
                    .foregroundStyle(theme.inkSecondary.opacity(0.6))
                    .help(result.literal ? "Name or accession match" : "Description match")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(theme.bgRaised)
        .contextMenu { FamilyActions(family: result.family) }
    }

    /// Debounced: MiniLM runs on every keystroke otherwise, and a 30,031-row
    /// gemv per character makes typing feel sticky.
    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { results = []; isSearching = false; return }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled, let engine = app.engine else { return }
            let found = (try? await engine.search(trimmed)) ?? []
            guard !Task.isCancelled else { return }
            results = found
            isSearching = false
        }
    }
}

#endif
