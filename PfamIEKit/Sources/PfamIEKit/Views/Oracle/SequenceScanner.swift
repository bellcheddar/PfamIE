import SwiftUI

#if canImport(VisionKit) && os(iOS)
import VisionKit

/// Reads a protein sequence off a printed page with the camera.
///
/// A conference poster, a paper, a whiteboard. Live text recognition returns
/// prose as well as residues, so the useful part is not the OCR: it is deciding
/// which of the recognised text is actually a sequence. `SequenceHarvester`
/// does that, and is tested independently of the camera.
struct SequenceScannerView: UIViewControllerRepresentable {

    @Binding var harvested: String
    let onFinish: (String) -> Void

    static var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let parent: SequenceScannerView
        private var harvester = SequenceHarvester()

        init(_ parent: SequenceScannerView) { self.parent = parent }

        func dataScanner(_ scanner: DataScannerViewController,
                         didAdd added: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            absorb(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController,
                         didUpdate updated: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            absorb(allItems)
        }

        private func absorb(_ items: [RecognizedItem]) {
            let strings: [String] = items.compactMap {
                if case .text(let text) = $0 { return text.transcript }
                return nil
            }
            harvester.absorb(strings)
            parent.harvested = harvester.sequence
        }
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .accurate,
            recognizesMultipleItems: true,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        try? controller.startScanning()
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: DataScannerViewController,
                                          coordinator: Coordinator) {
        controller.stopScanning()
    }
}
#endif

/// Turns whatever the camera reads into a protein sequence, or nothing.
///
/// Kept free of VisionKit so it can be tested without a camera, and because
/// the hard part is not the OCR. Printed sequences arrive in fragments, in any
/// order, mixed with figure captions and body text, and often re-read as the
/// camera moves. The rules below are what separate a sequence from prose.
public struct SequenceHarvester: Sendable {

    /// Fragments seen so far, in first-seen order and de-duplicated.
    private var fragments: [String] = []
    private var seen: Set<String> = []

    public init() {}

    /// The residues gathered so far.
    public private(set) var sequence: String = ""

    public mutating func absorb(_ transcripts: [String]) {
        for transcript in transcripts {
            for candidate in Self.sequenceLike(in: transcript) where !seen.contains(candidate) {
                seen.insert(candidate)
                fragments.append(candidate)
            }
        }
        sequence = fragments.joined()
    }

    public mutating func reset() {
        fragments.removeAll()
        seen.removeAll()
        sequence = ""
    }

    /// Minimum residues before a run is believed.
    ///
    /// 12 was not enough. Whitespace has to be skipped rather than treated as
    /// a separator, because printed sequences are conventionally broken into
    /// blocks of ten, and that means "PROTEIN FAMILY" joins into a 13-residue
    /// run. 20 puts ordinary two-word phrases out of reach.
    public static let minimumResidues = 20

    /// Distinct residues required, which rejects "AAAAAAAAAAAAAAAAAAAA" from a
    /// figure axis or a printed rule.
    public static let minimumDistinct = 8

    /// The twenty standard residues, deliberately *not* including the
    /// ambiguity codes B, J, O, U, X and Z that ESM-2 also accepts.
    ///
    /// This is the rule that separates a sequence from prose written in
    /// capitals, and it does so almost for free. O and U are among the
    /// commonest letters in English and are not standard amino acids, so
    /// "PROTEIN" breaks at the O and "SEQUENCE" breaks at the U. Allowing them
    /// let "THE ENTIRE PROTEIN FAMILY DATABASE" through as a 30-residue run.
    /// A real sequence containing an X simply yields two fragments, and both
    /// are collected.
    private static let standardResidues = Set("ACDEFGHIKLMNPQRSTVWY")

    /// The most distinctive English bigrams that survive the 20-letter
    /// residue alphabet, and the density above which a run is prose.
    ///
    /// Restricting the alphabet is not quite enough on its own: a long enough
    /// capitalised sentence still leaves a residue-only run, and "DOMAIN
    /// ARCHITECTURE AND FAMILY ASSIGNMENT" yields a 21-residue one. English
    /// bigram structure separates the two cleanly, because a protein sequence
    /// has almost none of it. Measured over 300 real Pfam seed sequences the
    /// density runs to a maximum of 0.148 (median 0.062, p99 0.140); the prose
    /// runs above start at 0.200. The threshold sits in that gap.
    private static let englishBigrams: Set<String> = [
        "TH", "HE", "IN", "ER", "AN", "RE", "ND", "AT", "ES", "EN",
        "ED", "TI", "IT", "AR", "TE", "AI", "IS", "HA", "ET", "SE",
    ]
    public static let maximumEnglishBigramDensity = 0.17

    /// Fraction of adjacent pairs that are common English bigrams.
    public static func englishBigramDensity(of run: String) -> Double {
        let characters = Array(run)
        guard characters.count >= 2 else { return 0 }
        var hits = 0
        for i in 0..<(characters.count - 1) where
            englishBigrams.contains(String(characters[i...i + 1])) {
            hits += 1
        }
        return Double(hits) / Double(characters.count - 1)
    }

    /// Pulls the runs of text that look like residues out of one transcript.
    public static func sequenceLike(in transcript: String) -> [String] {
        var found: [String] = []
        var current = ""

        func flush() {
            defer { current = "" }
            guard current.count >= minimumResidues else { return }
            guard Set(current).count >= minimumDistinct else { return }
            guard englishBigramDensity(of: current) <= maximumEnglishBigramDensity else { return }
            found.append(current)
        }

        for character in transcript {
            // Whitespace is skipped, not a separator: printed sequences are
            // conventionally written in blocks of ten.
            if character.isWhitespace { continue }
            if standardResidues.contains(character) {
                current.append(character)
            } else {
                flush()
            }
        }
        flush()
        return found
    }
}
