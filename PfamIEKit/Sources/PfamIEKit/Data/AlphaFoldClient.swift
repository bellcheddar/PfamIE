import Foundation

/// Fetches and caches AlphaFold predicted structures.
///
/// AlphaFold models are indexed by UniProt accession and numbered in UniProt
/// coordinates, which is why the structure layer uses them: a Pfam domain
/// range maps onto the model directly, with no residue-mapping step and no
/// SIFTS lookup.
public actor AlphaFoldClient {

    public enum FetchError: Error, CustomStringConvertible {
        case noModel(String)
        case service(String, Int)
        case offline(String)

        public var description: String {
            switch self {
            case .noModel(let accession):
                return "AlphaFold has no model for \(accession)."
            case .service(let accession, let code):
                return "AlphaFold returned \(code) for \(accession)."
            case .offline(let accession):
                return "\(accession) is not cached and there is no network."
            }
        }
    }

    private let cacheDirectory: URL
    private let session: URLSession
    private var inFlight: [String: Task<URL, Error>] = [:]

    public init(cacheDirectory: URL? = nil, session: URLSession = .shared) {
        let base = cacheDirectory ?? FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AlphaFold", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        self.cacheDirectory = base
        self.session = session
    }

    private func cachedURL(_ accession: String) -> URL {
        cacheDirectory.appendingPathComponent("\(accession).cif")
    }

    public func cachedStructure(for accession: String) -> URL? {
        let url = cachedURL(accession)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The mmCIF for an accession, from disk if it is there.
    ///
    /// Concurrent requests for the same accession share one download: the
    /// family card, the Oracle result and the Galaxy chip can all ask at once.
    public func structure(for accession: String) async throws -> URL {
        if let cached = cachedStructure(for: accession) { return cached }
        if let existing = inFlight[accession] { return try await existing.value }

        let task = Task<URL, Error> {
            defer { Task { await self.clearInFlight(accession) } }
            return try await self.download(accession)
        }
        inFlight[accession] = task
        return try await task.value
    }

    private func clearInFlight(_ accession: String) { inFlight[accession] = nil }

    private func download(_ accession: String) async throws -> URL {
        // The prediction endpoint gives the current model's URL. Building the
        // file name by hand means guessing the model version, which changes.
        let metadataURL = URL(
            string: "https://alphafold.ebi.ac.uk/api/prediction/\(accession)"
        )!

        let (data, response) = try await session.data(from: metadataURL)
        guard let http = response as? HTTPURLResponse else {
            throw FetchError.offline(accession)
        }
        guard http.statusCode == 200 else {
            throw FetchError.service(accession, http.statusCode)
        }

        struct Entry: Decodable { let cifUrl: String? }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        guard let cif = entries.first?.cifUrl, let cifURL = URL(string: cif) else {
            throw FetchError.noModel(accession)
        }

        let (fileData, cifResponse) = try await session.data(from: cifURL)
        guard (cifResponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw FetchError.noModel(accession)
        }

        let destination = cachedURL(accession)
        try fileData.write(to: destination, options: .atomic)
        return destination
    }

    public func cacheSizeBytes() -> Int {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        )) ?? []
        return contents.reduce(0) {
            $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
    }

    public func clearCache() {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory, includingPropertiesForKeys: nil
        )) ?? []
        for url in contents { try? FileManager.default.removeItem(at: url) }
    }
}
