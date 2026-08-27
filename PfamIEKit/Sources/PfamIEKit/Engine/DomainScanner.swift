import Foundation

/// Reads the domain architecture of a sequence by sliding a window along it.
///
/// The classifier compares a whole embedding against family centroids, so a
/// multi-domain protein embedded end to end returns a blend of its domains and
/// often names none of them. Scanning a window narrow enough to sit inside one
/// domain recovers the N-to-C order, which is what the Oracle's architecture
/// track and the Grammarian both need.
public struct DomainScanner: Sendable {

    public struct Configuration: Sendable {
        /// Window width in residues. Wide enough to carry a domain's signal,
        /// narrow enough that a 160-residue domain is not swamped by flanks.
        public var windowLength: Int = 160
        /// How far the window advances. A quarter of the width means every
        /// residue is covered by four windows, so a domain boundary is resolved
        /// to about 40 residues.
        public var stride: Int = 40
        /// A window must reach at least this calibrated probability before its
        /// call is believed at all.
        public var minimumWindowProbability: Float = 0.30
        /// A merged domain must reach this at its best window, or it is
        /// dropped: a run of individually weak windows is not evidence.
        public var minimumDomainProbability: Float = 0.50
        /// Domains shorter than this are noise from a single stray window.
        public var minimumDomainLength: Int = 40

        public init() {}
    }

    public struct DomainCall: Sendable, Hashable, Identifiable {
        public let row: Int
        /// 1-based, inclusive, in the coordinates of the sanitised sequence.
        public let start: Int
        public let end: Int
        public let bestProbability: Float
        public let meanProbability: Float
        public let windowCount: Int

        public var id: String { "\(row)-\(start)-\(end)" }
        public var length: Int { end - start + 1 }
        public var range: ClosedRange<Int> { start...end }
    }

    public struct Result: Sendable {
        /// Domains in N-to-C order.
        public let domains: [DomainCall]
        /// Whole-sequence classification, for the headline answer.
        public let whole: [CentroidIndex.Neighbour]
        public let residueCount: Int
        public let windowsScanned: Int
        /// True when the sequence was short enough that one window covered it,
        /// so the architecture track is really just the whole-sequence call.
        public let singleWindow: Bool
    }

    public var configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Window start offsets, 0-based, covering the whole sequence.
    ///
    /// The final window is pinned to the C-terminus rather than allowed to run
    /// off the end, so the last residues get the same coverage as the rest.
    /// Without that the C-terminal domain of every protein reads short.
    func windowStarts(residueCount: Int) -> [Int] {
        guard residueCount > configuration.windowLength else { return [0] }
        var starts: [Int] = []
        var offset = 0
        let last = residueCount - configuration.windowLength
        while offset < last {
            starts.append(offset)
            offset += configuration.stride
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
            return Result(domains: [], whole: [], residueCount: 0,
                          windowsScanned: 0, singleWindow: true)
        }

        let whole = index.search(try embedder.embed(residues: String(decoding: residues, as: UTF8.self)), k: 20)

        let starts = windowStarts(residueCount: count)
        if starts.count == 1 {
            let domains = whole.first.flatMap { best -> [DomainCall] in
                guard best.probability >= configuration.minimumDomainProbability else { return [] }
                return [DomainCall(row: best.row, start: 1, end: count,
                                   bestProbability: best.probability,
                                   meanProbability: best.probability, windowCount: 1)]
            } ?? []
            return Result(domains: domains, whole: whole, residueCount: count,
                          windowsScanned: 1, singleWindow: true)
        }

        // One call per window: row, its probability, and the span it covers.
        var calls: [(row: Int, probability: Float, start: Int, end: Int)] = []
        for start in starts {
            let end = min(start + configuration.windowLength, count)
            let window = String(decoding: residues[start..<end], as: UTF8.self)
            let hits = index.search(try embedder.embed(residues: window), k: 5)
            guard let best = hits.first,
                  best.probability >= configuration.minimumWindowProbability else {
                calls.append((row: -1, probability: 0, start: start + 1, end: end))
                continue
            }
            calls.append((row: best.row, probability: best.probability,
                          start: start + 1, end: end))
        }

        var domains: [DomainCall] = []
        var runStart = 0
        while runStart < calls.count {
            let row = calls[runStart].row
            if row < 0 { runStart += 1; continue }

            var runEnd = runStart
            while runEnd + 1 < calls.count && calls[runEnd + 1].row == row { runEnd += 1 }

            let run = calls[runStart...runEnd]
            let best = run.map(\.probability).max() ?? 0
            let mean = run.map(\.probability).reduce(0, +) / Float(run.count)
            let from = run.first!.start
            let to = run.last!.end

            if best >= configuration.minimumDomainProbability,
               to - from + 1 >= configuration.minimumDomainLength {
                domains.append(DomainCall(row: row, start: from, end: to,
                                          bestProbability: best, meanProbability: mean,
                                          windowCount: run.count))
            }
            runStart = runEnd + 1
        }

        return Result(domains: domains, whole: whole, residueCount: count,
                      windowsScanned: starts.count, singleWindow: false)
    }
}
