import SwiftUI
// The watch companion shares the engine, the models and the theme, but none of
// the phone and desktop UI: it carries no assets and shows one glance view.
// SwiftUI on watchOS also lacks TextEditor, fileImporter, textSelection,
// segmented pickers and keyboard shortcuts, so compiling these views there
// fails on about a dozen counts. Excluding them is the honest description of
// the architecture as well as the fix, and it keeps the watch binary small.
#if !os(watchOS)

/// Appearance, cache and provenance.
///
/// The provenance section is not decoration. This app makes claims about
/// protein families, and a reader is entitled to know which Pfam release, which
/// model, and how often it is right, without taking any of it on trust.
public struct SettingsSheet: View {
    @Environment(\.theme) private var theme
    @Environment(AppEnvironment.self) private var app
    @Environment(StructureCache.self) private var cache
    @Environment(\.dismiss) private var dismiss

    @State private var cacheBytes = 0

    public init() {}

    public var body: some View {
        @Bindable var app = app

        NavigationStack {
            Form {
                Section("Appearance") {
                    Picker("Appearance", selection: $app.appearance) {
                        ForEach(AppearanceChoice.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    ForEach(app.provenance, id: \.0) { label, value in
                        LabeledContent(label) {
                            Text(value)
                                .font(.system(.footnote, design: .monospaced))
                                .foregroundStyle(theme.inkSecondary)
                        }
                    }
                } header: {
                    Text("What this app is built on")
                } footer: {
                    Text("The two accuracy figures measure different things. Real "
                         + "proteins are what you paste in. Held-out Pfam seed sequences "
                         + "are trimmed to domain boundaries and come from the same "
                         + "alignments the index was built from, so they flatter it by "
                         + "about thirty points. Confidence is calibrated on the former.")
                        .font(.caption)
                }

                Section {
                    LabeledContent("Structure cache") {
                        Text(cacheBytes.formatted(.byteCount(style: .file)))
                            .font(.system(.footnote, design: .monospaced))
                    }
                    Button("Clear cached structures", role: .destructive) {
                        Task {
                            await cache.client.clearCache()
                            cacheBytes = await cache.client.cacheSizeBytes()
                        }
                    }
                    .disabled(cacheBytes == 0)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("AlphaFold models are downloaded once and kept. Everything "
                         + "else, including all classification and search, runs with no "
                         + "network at all.")
                        .font(.caption)
                }

                Section("About") {
                    LabeledContent("PfamIE", value: "1.0")
                    Link("marcdeller.com", destination: URL(string: "https://marcdeller.com")!)
                    Link("Pfam at InterPro",
                         destination: URL(string: "https://www.ebi.ac.uk/interpro/")!)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(theme.bgDeep)
            .navigationTitle("Settings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { cacheBytes = await cache.client.cacheSizeBytes() }
        }
    }
}

#endif
