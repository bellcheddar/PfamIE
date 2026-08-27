import Foundation

/// Reads the domain architecture of a sequence by scanning it at several
/// window widths.
///
/// Measured on 400 real single-domain UniProt proteins, ranked against all
/// 30,031 families (with ESM-2 t6-8M, which is what the comparison was run on;
/// t12-35M lifts every row but the ordering is the point):
///
///   whole sequence only        top-1 0.285   top-5 0.435
///   one 160-residue window     top-1 0.425   top-5 0.548
///   96 / 160 / 256 / 384       top-1 0.535   top-5 0.635
///
/// Two things that table settles. A real protein is not a trimmed domain: it
/// carries signal peptides, linkers and disordered tails, and embedding it end
/// to end averages all of that into the answer, which is why the whole-sequence
/// number is the worst of the three. And no single window width fits Pfam,
/// whose domains run from about 30 residues to several hundred, so scanning at
/// four widths recovers a quarter more families than the best single width.
/// Multi-scale costs inference time only, nothing in bundle size.
///
/// Held-out Pfam seed sequences score around 0.75 on the same task. They are
/// domain-trimmed and drawn from the alignments the centroids came from, so
/// that number describes the index, not the app. On real proteins the shipped
/// t12-35M index scores 0.49 top-1, and finds 47.8% of the domains in a
/// multi-domain protein at 0.84 precision.
public struct DomainScanner: Sendable {

    public struct Scale: Sendable, Hashable {
        public let windowLength: Int
        public let stride: Int
        public init(windowLength: Int, stride: Int) {
            self.windowLength = windowLength
            self.stride = stride
        }
    }

    public struct Configuration: Sendable {
        /// Widths to scan at, narrowest first. Strides are about a third of the
        /// width, so a boundary is resolved to roughly that.
        public var scales: [Scale] = [
            Scale(windowLength: 96, stride: 32),
            Scale(windowLength: 160, stride: 48),
            Scale(windowLength: 256, stride: 64),
            Scale(windowLength: 384, stride: 96),
        ]
        /// A window's call is ignored below this calibrated probability.
        public var minimumWindowProbability: Float = 0.30
        /// A merged domain needs this at its best window to be reported.
        public var minimumDomainProbability: Float = 0.45
        public var minimumDomainLength: Int = 30
        /// How much two accepted domains may overlap, as a fraction of the
        /// shorter one. Domains genuinely abut, and windows are coarse, so a
        /// little overlap is expected; a lot means the same domain called twice
        /// at two scales.
        public var overlapTolerance: Double = 0.35
        /// Cap on windows per scan, so a 4,000-residue protein cannot spend a
        /// minute on the Neural Engine.
        public var maximumWindows: Int = 220

        public init() {}
    }

    public struct DomainCall: Sendable, Hashable, Identifiable {
        public let row: Int
        /// 1-based and inclusive, in the coordinates of the sanitised sequence.
        public let start: Int
        public let end: Int
        public let bestProbability: Float
        public let bestSimilarity: Float
        /// The window width that called it, which is worth surfacing: a domain
        /// only seen at 384 is a large one, and a 96-only call is a fragment.
        public let scale: Int
        public let windowCount: Int

        public var id: String { "\(row)-\(start)-\(end)" }
        public var length: Int { end - start + 1 }
        public var range: ClosedRange<Int> { start...end }
    }

    public struct Result: Sendable {
        /// Accepted domains, N to C.
        public let domains: [DomainCall]
        /// Ranked families for the headline answer. This is the best-scoring
        /// window's shortlist, not the whole-sequence one, because the
        /// whole-sequence embedding is measurably the weakest signal available.
        public let headline: [CentroidIndex.Neighbour]
        /// Whole-sequence ranking, kept for the "the protein overall" case.
        public let wholeSequence: [CentroidIndex.Neighbour]
        /// Where the headline call came from, or nil if it was whole-sequence.
        public let headlineRange: ClosedRange<Int>?
        public let residueCount: Int
        public let windowsScanned: Int
        public let singleWindow: Bool
    }

    public var configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Window offsets for one scale, 0-based.
    ///
    /// The last window is pinned to the C-terminus rather than allowed to run
    /// off the end. Without that the final residues get less coverage than the
    /// rest and every protein's C-terminal domain reads short.
    func windowStarts(residueCount: Int, scale: Scale) -> [Int] {
        guard residueCount > scale.windowLength else { return [0] }
        var starts: [Int] = []
        var offset = 0
        let last = residueCount - scale.windowLength
        while offset < last {
            starts.append(offset)
            offset += scale.stride
        }
        starts.append(last)
        return starts
    }

    public func scan(
        sequence: String,
        embedder: ProteinEmbedder,
        index: CentroidIndex
    ) throws -> Result {
        let residues = Array(ProteinTokenizer.sanitise(sequence).utf8)
        let count = residues.count
        guard count > 0 else {
            return Result(domains: [], headline: [], wholeSequence: [],
                          headlineRange: nil, residueCount: 0,
                          windowsScanned: 0, singleWindow: true)
        }

        let wholeText = String(decoding: residues.prefix(ProteinTokenizer.maxResidues), as: UTF8.self)
        let whole = index.search(try embedder.embed(residues: wholeText), k: 20)

        // Only scan at widths the sequence can actually accommodate, plus the
        // narrowest one always, so a 60-residue peptide still gets scanned.
        var scales = configuration.scales.filter { $0.windowLength <= count }
        if scales.isEmpty { scales = [configuration.scales[0]] }

        var candidates: [DomainCall] = []
        var best: (neighbours: [CentroidIndex.Neighbour], range: ClosedRange<Int>)?
        var scanned = 0

        for scale in scales {
            let starts = windowStarts(residueCount: count, scale: scale)
            guard scanned + starts.count <= configuration.maximumWindows else { break }

            var calls: [(row: Int, probability: Float, similarity: Float, start: Int, end: Int)] = []
            for start in starts {
                let end = min(start + scale.windowLength, count)
                let window = String(decoding: residues[start..<end], as: UTF8.self)
                let hits = index.search(try embedder.embed(residues: window), k: 20)
                scanned += 1

                guard let top = hits.first else {
                    calls.append((-1, 0, 0, start + 1, end))
                    continue
                }
                if best == nil || top.probability > (best!.neighbours.first?.probability ?? 0) {
                    best = (hits, (start + 1)...end)
                }
                if top.probability >= configuration.minimumWindowProbability {
                    calls.append((top.row, top.probability, top.similarity, start + 1, end))
                } else {
                    calls.append((-1, 0, 0, start + 1, end))
                }
            }
            candidates.append(contentsOf: merge(calls: calls, scale: scale.windowLength))
        }

        let domains = selectNonOverlapping(candidates)

        // The headline is the best window unless the whole sequence beat it,
        // which happens for a protein that really is one domain end to end.
        var headline = best?.neighbours ?? whole
        var headlineRange = best?.range
        if let wholeTop = whole.first,
           wholeTop.probability >= (headline.first?.probability ?? 0) {
            headline = whole
            headlineRange = nil
        }

        return Result(
            domains: domains,
            headline: headline,
            wholeSequence: whole,
            headlineRange: headlineRange,
            residueCount: count,
            windowsScanned: scanned,
            singleWindow: scanned <= 1
        )
    }

    /// Runs of adjacent windows calling the same family become one domain.
    private func merge(
        calls: [(row: Int, probability: Float, similarity: Float, start: Int, end: Int)],
        scale: Int
    ) -> [DomainCall] {
        var out: [DomainCall] = []
        var runStart = 0
        while runStart < calls.count {
            let row = calls[runStart].row
            if row < 0 { runStart += 1; continue }

            var runEnd = runStart
            while runEnd + 1 < calls.count && calls[runEnd + 1].row == row { runEnd += 1 }
            let run = calls[runStart...runEnd]

            let bestProbability = run.map(\.probability).max() ?? 0
            let bestSimilarity = run.map(\.similarity).max() ?? 0
            let from = run.first!.start
            let to = run.last!.end

            if bestProbability >= configuration.minimumDomainProbability,
               to - from + 1 >= configuration.minimumDomainLength {
                out.append(DomainCall(
                    row: row, start: from, end: to,
                    bestProbability: bestProbability, bestSimilarity: bestSimilarity,
                    scale: scale, windowCount: run.count
                ))
            }
            runStart = runEnd + 1
        }
        return out
    }

    /// Greedy selection by confidence: take the strongest call, then the next
    /// strongest that does not substantially overlap anything already taken.
    ///
    /// Scanning at four widths means the same domain is proposed several times,
    /// once per scale. Reporting all of them would draw a stack of overlapping
    /// lozenges for one domain.
    private func selectNonOverlapping(_ candidates: [DomainCall]) -> [DomainCall] {
        var accepted: [DomainCall] = []
        for candidate in candidates.sorted(by: { $0.bestProbability > $1.bestProbability }) {
            let clashes = accepted.contains { existing in
                let overlap = min(existing.end, candidate.end) - max(existing.start, candidate.start) + 1
                guard overlap > 0 else { return false }
                let shorter = Double(min(existing.length, candidate.length))
                return Double(overlap) / shorter > configuration.overlapTolerance
            }
            if !clashes { accepted.append(candidate) }
        }
        return accepted.sorted { $0.start < $1.start }
    }
}
