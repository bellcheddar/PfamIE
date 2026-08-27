import SwiftUI
import UniformTypeIdentifiers
// The watch companion shares the engine, the models and the theme, but none of
// the phone and desktop UI: it carries no assets and shows one glance view.
// SwiftUI on watchOS also lacks TextEditor, fileImporter, textSelection,
// segmented pickers and keyboard shortcuts, so compiling these views there
// fails on about a dozen counts. Excluding them is the honest description of
// the architecture as well as the fix, and it keeps the watch binary small.
#if !os(watchOS)

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
    @State private var showingScanner = false
    @State private var scanned = ""
    @State private var verifying = false
    @State private var verifyStatus = ""
    @State private var verification: [InterProScanClient.Match]?
    @State private var verifyError: String?
    @State private var confirmingVerify = false
    @State private var verifyTask: Task<Void, Never>?
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
        .navigationTitle(AppTab.oracle.title)
        // Vision Pro has no haptics, and the modifier is visionOS 26 only.
        #if !os(visionOS)
        .sensoryFeedback(.success, trigger: result?.residueCount)
        #endif
        #if canImport(VisionKit) && os(iOS)
        .sheet(isPresented: $showingScanner) { scannerSheet }
        #endif
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

                #if canImport(VisionKit) && os(iOS)
                if SequenceScannerView.isAvailable {
                    Button("Scan", systemImage: "camera.viewfinder") {
                        scanned = ""
                        showingScanner = true
                    }
                    .buttonStyle(.bordered)
                }
                #endif

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
                            // Say where the call came from. The headline is the
                            // best-reading window, not the whole sequence, and
                            // "a Pkinase domain at 270-520" is a more useful
                            // and more honest claim than "this is a Pkinase".
                            if let range = result.headlineRange {
                                Label(
                                    "Read from residues \(range.lowerBound) to \(range.upperBound)",
                                    systemImage: "scope"
                                )
                                .font(.caption)
                                .foregroundStyle(theme.inkSecondary)
                            }
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
                    domains: result.domains
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

            verificationSection(result)

            Group {
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

    /// The one network path in the app, and it says so before using it.
    @ViewBuilder
    private func verificationSection(_ result: PfamIEEngine.Classification) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeading("Check against InterProScan", detail: nil)

            if let matches = verification {
                if matches.isEmpty {
                    Text("InterProScan found no Pfam match in this sequence.")
                        .font(.footnote).foregroundStyle(theme.inkSecondary)
                } else {
                    ForEach(matches) { match in
                        HStack(spacing: 10) {
                            Image(systemName: agreementSymbol(match, result))
                                .foregroundStyle(agreementColour(match, result))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(match.name) \(match.accession)")
                                    .font(.system(.subheadline, design: .rounded))
                                Text("residues \(match.start) to \(match.end)")
                                    .font(.caption).foregroundStyle(theme.inkSecondary)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(theme.bgRaised,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    Text("A tick means PfamIE called the same family. This is the "
                         + "authoritative answer; PfamIE is an approximation of it.")
                        .font(.caption).foregroundStyle(theme.inkSecondary)
                }
            } else if verifying {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(verifyStatus).font(.footnote).foregroundStyle(theme.inkSecondary)
                    Spacer()
                    Button("Cancel") { verifyTask?.cancel(); verifying = false }
                        .font(.footnote)
                }
            } else if let verifyError {
                Label(verifyError, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(theme.accentFlare)
                    .fixedSize(horizontal: false, vertical: true)
            } else if app.canVerifyOnline {
                Button("Verify online with InterProScan", systemImage: "network") {
                    confirmingVerify = true
                }
                .buttonStyle(.bordered)
                .font(.footnote)
            } else {
                Text("Add your email in Settings to check this call against "
                     + "InterProScan at EMBL-EBI. Everything else works offline.")
                    .font(.footnote).foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .confirmationDialog(
            "Send this sequence to EMBL-EBI?",
            isPresented: $confirmingVerify,
            titleVisibility: .visible
        ) {
            Button("Send \(result.residueCount) residues") { verifyOnline(result) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This is the only part of PfamIE that leaves your device. Your "
                 + "sequence and your email address go to InterProScan 5 at "
                 + "EMBL-EBI, subject to their terms of use.")
        }
    }

    private func agreementSymbol(
        _ match: InterProScanClient.Match,
        _ result: PfamIEEngine.Classification
    ) -> String {
        agrees(match, result) ? "checkmark.circle.fill" : "circle.dashed"
    }

    private func agreementColour(
        _ match: InterProScanClient.Match,
        _ result: PfamIEEngine.Classification
    ) -> Color {
        agrees(match, result) ? theme.confidenceHigh : theme.inkSecondary
    }

    private func agrees(
        _ match: InterProScanClient.Match,
        _ result: PfamIEEngine.Classification
    ) -> Bool {
        let called = Set(result.domains.map(\.family.accession.rawValue)
                         + result.hits.prefix(1).map(\.family.accession.rawValue))
        return called.contains(match.accession)
    }

    private func verifyOnline(_ result: PfamIEEngine.Classification) {
        verifyError = nil
        verification = nil
        verifying = true
        verifyStatus = "Submitting"

        verifyTask = Task {
            do {
                let outcome = try await InterProScanClient().verify(
                    sequence: result.sequence,
                    email: app.verificationEmail,
                    onStatus: { status in Task { @MainActor in verifyStatus = status } }
                )
                verification = outcome.matches
            } catch is CancellationError {
                verifyError = nil
            } catch {
                verifyError = String(describing: error)
            }
            verifying = false
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

    #if canImport(VisionKit) && os(iOS)
    private var scannerSheet: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                SequenceScannerView(harvested: $scanned) { _ in }
                    .ignoresSafeArea()

                VStack(spacing: 8) {
                    Text(scanned.isEmpty
                         ? "Point the camera at a printed sequence"
                         : "\(scanned.count) residues read")
                        .font(.footnote.weight(.medium))
                    if !scanned.isEmpty {
                        Text(scanned.prefix(60) + (scanned.count > 60 ? "..." : ""))
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(1)
                            .foregroundStyle(theme.inkSecondary)
                    }
                    Button("Use this sequence") {
                        input = scanned
                        showingScanner = false
                        Task { await classify() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accentNova)
                    .disabled(scanned.count < 12)
                }
                .padding(16)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding()
            }
            .navigationTitle("Scan a sequence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showingScanner = false }
                }
            }
        }
    }
    #endif

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

            #if canImport(WatchConnectivity) && os(iOS)
            let clanName = outcome.hits.first
                .flatMap(\.family.clan)
                .flatMap { app.clanByAccession[$0]?.identifier }
            WatchBridge.shared.send(outcome, clanName: clanName)
            #endif
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

#endif
