import SwiftUI
import UniformTypeIdentifiers

/// Paste a sequence, get a family, a clan and an architecture.
public struct OracleView: View {
    @Environment(\.theme) private var theme
    @Environment(AppEnvironment.self) private var app
    @Environment(Router.self) private var router

    @State private var input: String = ""
    @State private var isClassifying = false
    @State private var result: PfamIEEngine.Classification?
    @State private var failure: String?
    @State private var showingImporter = false
    @FocusState private var inputFocused: Bool

    public init() {}

    private var residueCount: Int { ProteinTokenizer.sanitise(input).count }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                inputCard
                if let failure { errorCard(failure) }
                if let result { resultSection(result) }
                else if !isClassifying { emptyState }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(theme.bgDeep)
        .navigationTitle(Tab.oracle.title)
        .sensoryFeedback(.success, trigger: result?.residueCount)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [.plainText, .data],
            allowsMultipleSelection: false
        ) { outcome in
            handleImport(outcome)
        }
        .onAppear {
            if let prefill = router.consumeOraclePrefill() {
                input = prefill
                Task { await classify() }
            }
        }
        .onChange(of: router.oraclePrefill) { _, new in
            guard let new else { return }
            input = new
            _ = router.consumeOraclePrefill()
            Task { await classify() }
        }
    }

    // MARK: - Input

    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Sequence", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                if residueCount > 0 {
                    Text("\(residueCount) aa")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(theme.inkSecondary)
                        .contentTransition(.numericText())
                }
            }

            TextEditor(text: $input)
                .font(.system(.footnote, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(theme.bgDeep.opacity(0.6))
                .frame(minHeight: 132)
                .focused($inputFocused)
                .overlay(alignment: .topLeading) {
                    if input.isEmpty {
                        Text("Paste an amino-acid sequence or FASTA record")
                            .font(.system(.footnote, design: .monospaced))
                            .foregroundStyle(theme.inkSecondary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 8)
                            .allowsHitTesting(false)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(theme.hairline)
                )

            if residueCount > ProteinTokenizer.maxResidues {
                Label(
                    "Only the first \(ProteinTokenizer.maxResidues) residues are embedded whole. "
                    + "The architecture scan still covers the full length.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(theme.accentFlare)
            }

            HStack(spacing: 10) {
                Button {
                    Task { await classify() }
                } label: {
                    if isClassifying {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Reading")
                        }
                    } else {
                        Label("Classify", systemImage: "wand.and.stars")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(theme.accentNova)
                .disabled(residueCount < 12 || isClassifying)

                Button("Open file", systemImage: "doc") { showingImporter = true }
                    .buttonStyle(.bordered)

                if !input.isEmpty {
                    Button("Clear", systemImage: "xmark") {
                        input = ""; result = nil; failure = nil
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            }
            .labelStyle(.titleAndIcon)
        }
        .padding(16)
        .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.hairline))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 34))
                .foregroundStyle(theme.accentNova.opacity(0.7))
            Text("The Oracle awaits a sequence")
                .font(.headline)
            Text("Everything happens on this device. No sequence leaves it.")
                .font(.footnote)
                .foregroundStyle(theme.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.footnote)
            .foregroundStyle(theme.confidenceLow)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.confidenceLow.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Result

    @ViewBuilder
    private func resultSection(_ result: PfamIEEngine.Classification) -> some View {
        let calibration = app.engine?.calibration

        VStack(alignment: .leading, spacing: 18) {
            if let top = result.hits.first, let calibration {
                HStack(alignment: .top, spacing: 18) {
                    ConfidenceRing(probability: top.probability, calibration: calibration)

                    VStack(alignment: .leading, spacing: 6) {
                        if result.isConfident {
                            Text(top.family.displayName)
                                .font(.system(.title2, design: .rounded, weight: .semibold))
                            Text(top.family.summary)
                                .font(.subheadline)
                                .foregroundStyle(theme.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("No confident family")
                                .font(.system(.title3, design: .rounded, weight: .semibold))
                                .foregroundStyle(theme.inkSecondary)
                            Text("The nearest families are listed below as leads.")
                                .font(.subheadline)
                                .foregroundStyle(theme.inkSecondary)
                        }

                        HStack(spacing: 8) {
                            FamilyChip(family: top.family, showsAccession: true,
                                       tint: app.clanColour(for: top.family, theme: theme))
                            if let clan = top.family.clan,
                               let record = app.clanByAccession[clan] {
                                Text(record.identifier ?? clan.rawValue)
                                    .font(.caption)
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(theme.accentPulsar.opacity(0.15), in: Capsule())
                                    .foregroundStyle(theme.accentPulsar)
                            }
                        }
                        .padding(.top, 2)
                    }
                    Spacer(minLength: 0)
                }

                CalibrationNote(band: result.band, calibration: calibration)
            }

            if !result.singleDomainOnly {
                sectionHeading("Domain architecture",
                               detail: "\(result.windowsScanned) windows scanned")
                ArchitectureTrack(
                    residueCount: result.residueCount,
                    domains: result.domains,
                    colourFor: { app.clanColour(for: $0, theme: theme) }
                )
                if !result.domains.isEmpty {
                    Button("What else is built like this?",
                           systemImage: "puzzlepiece.extension") {
                        router.go(.grammarian(
                            architecture: result.domains.map(\.family.accession)
                        ))
                    }
                    .buttonStyle(.bordered)
                    .font(.footnote)
                }
            }

            sectionHeading("Nearest families", detail: nil)
            VStack(spacing: 0) {
                ForEach(result.hits) { hit in
                    hitRow(hit, calibration: calibration)
                    if hit.id != result.hits.last?.id { Divider().overlay(theme.hairline) }
                }
            }
            .background(theme.bgRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(theme.hairline))
        }
    }

    private func sectionHeading(_ title: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline)
            Spacer()
            if let detail {
                Text(detail).font(.caption).foregroundStyle(theme.inkSecondary)
            }
        }
    }

    private func hitRow(
        _ hit: PfamIEEngine.Classification.Hit,
        calibration: Calibration?
    ) -> some View {
        Button {
            router.go(.family(hit.family.accession))
        } label: {
            HStack(spacing: 12) {
                Circle()
                    .fill(app.clanColour(for: hit.family, theme: theme))
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.family.displayName)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                    Text(hit.family.summary)
                        .font(.caption)
                        .foregroundStyle(theme.inkSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(hit.probability, format: .percent.precision(.fractionLength(0)))
                    .font(.system(.caption, design: .rounded, weight: .semibold))
                    .foregroundStyle(
                        calibration.map { theme.colour(for: $0.band(for: hit.probability)) }
                        ?? theme.inkSecondary
                    )
                    .monospacedDigit()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu { FamilyActions(family: hit.family) }
    }

    // MARK: - Actions

    private func classify() async {
        guard let engine = app.engine else { return }
        let sequence = input
        isClassifying = true
        failure = nil
        inputFocused = false
        defer { isClassifying = false }

        do {
            let outcome = try await engine.classify(sequence: sequence)
            result = outcome
            app.lastClassification = outcome
        } catch {
            failure = "Could not classify that sequence: \(error)"
            result = nil
        }
    }

    private func handleImport(_ outcome: Result<[URL], Error>) {
        switch outcome {
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                input = try String(contentsOf: url, encoding: .utf8)
                Task { await classify() }
            } catch {
                failure = "Could not read \(url.lastPathComponent)."
            }
        case .failure(let error):
            failure = "Could not open that file: \(error.localizedDescription)"
        }
    }
}

extension PfamIEEngine.Classification {
    /// True when the sequence was short enough that the architecture track
    /// would only restate the headline call.
    var singleDomainOnly: Bool {
        windowsScanned <= 1
    }
}
