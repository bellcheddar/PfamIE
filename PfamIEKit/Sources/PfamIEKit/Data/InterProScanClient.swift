import Foundation

/// Checks a classification against InterProScan 5 at EMBL-EBI.
///
/// This is the only thing in PfamIE that sends anything anywhere, and the app
/// says so before it does. Everything else, including all classification,
/// architecture and search, runs on device with no network. A tool whose pitch
/// is "your sequence never leaves the phone" has to be scrupulous about its one
/// exception.
///
/// InterProScan rather than HMMER: EBI's hmmscan POST endpoint returns 405 and
/// the maintained route is InterProScan 5, which is also the authoritative
/// answer for what Pfam actually assigns. That is the thing PfamIE is
/// approximating, so it is the right yardstick.
public actor InterProScanClient {

    private static let base = "https://www.ebi.ac.uk/Tools/services/rest/iprscan5"

    public enum ScanError: Error, CustomStringConvertible {
        case noEmail
        case submissionFailed(String)
        case jobFailed(String)
        case timedOut
        case cancelled

        public var description: String {
            switch self {
            case .noEmail:
                return "EMBL-EBI requires an email address for job submission. Add yours in Settings."
            case .submissionFailed(let detail):
                return "InterProScan would not accept the job: \(detail)"
            case .jobFailed(let status):
                return "The InterProScan job ended as \(status)."
            case .timedOut:
                return "InterProScan did not finish in time. The job may still complete on their side."
            case .cancelled:
                return "Cancelled."
            }
        }
    }

    /// One Pfam match as InterProScan reports it.
    public struct Match: Sendable, Hashable, Identifiable {
        public let accession: String
        public let name: String
        public let start: Int
        public let end: Int
        public let evalue: Double?

        public var id: String { "\(accession)-\(start)-\(end)" }
    }

    public struct Outcome: Sendable {
        public let jobID: String
        public let matches: [Match]
    }

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    /// Submits, polls and parses. Cancelling the surrounding task stops the poll.
    public func verify(
        sequence: String,
        email: String,
        onStatus: @Sendable (String) -> Void = { _ in }
    ) async throws -> Outcome {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedEmail.contains("@") else { throw ScanError.noEmail }

        let residues = ProteinTokenizer.sanitise(sequence)
        guard residues.count >= 12 else {
            throw ScanError.submissionFailed("the sequence is too short")
        }

        onStatus("Submitting to EMBL-EBI")
        let jobID = try await submit(residues: residues, email: trimmedEmail)

        // InterProScan takes tens of seconds to a few minutes. Poll gently:
        // this is a shared public service, not an endpoint to hammer.
        var waited: TimeInterval = 0
        let deadline: TimeInterval = 300
        var interval: TimeInterval = 3

        while waited < deadline {
            try Task.checkCancellation()
            let status = try await status(of: jobID)
            onStatus(status == "RUNNING" ? "Running at EMBL-EBI" : status.capitalized)

            switch status {
            case "FINISHED":
                return Outcome(jobID: jobID, matches: try await matches(of: jobID))
            case "RUNNING", "PENDING", "QUEUED":
                break
            default:
                throw ScanError.jobFailed(status)
            }

            try await Task.sleep(for: .seconds(interval))
            waited += interval
            interval = min(interval * 1.4, 15)
        }
        throw ScanError.timedOut
    }

    private func submit(residues: String, email: String) async throws -> String {
        var request = URLRequest(url: URL(string: "\(Self.base)/run")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("text/plain", forHTTPHeaderField: "Accept")

        func encode(_ value: String) -> String {
            var allowed = CharacterSet.alphanumerics
            allowed.insert(charactersIn: "-._~")
            return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        }

        let body = [
            "email=\(encode(email))",
            "sequence=\(encode(">query\n" + residues))",
            "appl=PfamA",
            "goterms=false",
            "pathways=false",
        ].joined(separator: "&")
        request.httpBody = Data(body.utf8)

        let (data, response) = try await session.data(for: request)
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ScanError.submissionFailed(text.isEmpty ? "no response" : text)
        }
        guard text.hasPrefix("iprscan5-") else {
            throw ScanError.submissionFailed(text)
        }
        return text
    }

    private func status(of jobID: String) async throws -> String {
        let url = URL(string: "\(Self.base)/status/\(jobID)")!
        let (data, _) = try await session.data(from: url)
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func matches(of jobID: String) async throws -> [Match] {
        let url = URL(string: "\(Self.base)/result/\(jobID)/json")!
        let (data, _) = try await session.data(from: url)
        return Self.parse(json: data)
    }

    /// Pulls the Pfam matches out of an InterProScan 5 JSON result.
    ///
    /// Split out and made static so it can be tested against a captured
    /// response without contacting EBI at all.
    public static func parse(json data: Data) -> [Match] {
        struct Response: Decodable {
            struct Result: Decodable {
                struct MatchEntry: Decodable {
                    struct Signature: Decodable {
                        let accession: String?
                        let name: String?
                        struct Library: Decodable { let library: String? }
                        let signatureLibraryRelease: Library?
                    }
                    struct Location: Decodable {
                        let start: Int?
                        let end: Int?
                    }
                    let signature: Signature?
                    let locations: [Location]?
                    let evalue: Double?
                }
                let matches: [MatchEntry]?
            }
            let results: [Result]?
        }

        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            return []
        }
        var out: [Match] = []
        for result in decoded.results ?? [] {
            for entry in result.matches ?? [] {
                guard let signature = entry.signature,
                      let accession = signature.accession,
                      accession.hasPrefix("PF") else { continue }
                for location in entry.locations ?? [] {
                    guard let start = location.start, let end = location.end else { continue }
                    out.append(Match(
                        accession: accession,
                        name: signature.name ?? accession,
                        start: start,
                        end: end,
                        evalue: entry.evalue
                    ))
                }
            }
        }
        return out.sorted { $0.start < $1.start }
    }
}
