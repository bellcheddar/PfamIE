import Foundation
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Read-only access to pfam.sqlite.
///
/// Raw sqlite3 rather than a wrapper library: the package stays dependency
/// free, and every query in the app is one of the dozen below.
public final class PfamStore: @unchecked Sendable {

    public enum StoreError: Error, CustomStringConvertible {
        case cannotOpen(String)
        case cannotPrepare(String, String)

        public var description: String {
            switch self {
            case .cannotOpen(let path):
                return "Could not open the Pfam database at \(path)."
            case .cannotPrepare(let sql, let message):
                return "Query failed (\(message)): \(sql)"
            }
        }
    }

    private let handle: OpaquePointer
    private let lock = NSLock()

    public init(url: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK,
              let opened = handle else {
            throw StoreError.cannotOpen(url.path)
        }
        self.handle = opened
        sqlite3_exec(opened, "PRAGMA temp_store = MEMORY;", nil, nil, nil)
        sqlite3_exec(opened, "PRAGMA mmap_size = 268435456;", nil, nil, nil)
    }

    deinit { sqlite3_close_v2(handle) }

    // MARK: - Query plumbing

    private func query<T>(
        _ sql: String,
        bind: (OpaquePointer) -> Void = { _ in },
        row: (OpaquePointer) -> T
    ) throws -> [T] {
        lock.lock()
        defer { lock.unlock() }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let prepared = statement else {
            throw StoreError.cannotPrepare(sql, String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(prepared) }

        bind(prepared)

        var out: [T] = []
        while sqlite3_step(prepared) == SQLITE_ROW {
            out.append(row(prepared))
        }
        return out
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: raw)
    }

    private static func bindText(_ statement: OpaquePointer, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    // MARK: - Families

    private static let familyColumns = """
        row, accession, version, identifier, description, abstract, type, clan,
        is_duf, seed_count, n_proteins, n_taxa, n_structures, n_architectures,
        rep_uniprot, rep_start, rep_end, rep_length, x, y, z
        """

    private static func family(from s: OpaquePointer) -> Family {
        let uniprot = text(s, 14)
        let representative = uniprot.map {
            Representative(
                uniprot: $0,
                start: Int(sqlite3_column_int(s, 15)),
                end: Int(sqlite3_column_int(s, 16)),
                length: Int(sqlite3_column_int(s, 17))
            )
        }
        return Family(
            row: Int(sqlite3_column_int(s, 0)),
            accession: PfamID(text(s, 1) ?? ""),
            version: text(s, 2) ?? "",
            identifier: text(s, 3) ?? "",
            summary: text(s, 4) ?? "",
            abstract: text(s, 5) ?? "",
            type: EntryType(pfamValue: text(s, 6)),
            clan: text(s, 7).map(ClanID.init),
            isDUF: sqlite3_column_int(s, 8) != 0,
            seedCount: Int(sqlite3_column_int(s, 9)),
            proteinCount: Int(sqlite3_column_int(s, 10)),
            taxonCount: Int(sqlite3_column_int(s, 11)),
            structureCount: Int(sqlite3_column_int(s, 12)),
            architectureCount: Int(sqlite3_column_int(s, 13)),
            representative: representative,
            position: SIMD3<Float>(
                Float(sqlite3_column_double(s, 18)),
                Float(sqlite3_column_double(s, 19)),
                Float(sqlite3_column_double(s, 20))
            )
        )
    }

    public func familyCount() throws -> Int {
        try query("SELECT COUNT(*) FROM family") { Int(sqlite3_column_int($0, 0)) }.first ?? 0
    }

    public func family(row: Int) throws -> Family? {
        try query("SELECT \(Self.familyColumns) FROM family WHERE row = ?",
                  bind: { sqlite3_bind_int($0, 1, Int32(row)) },
                  row: Self.family).first
    }

    public func family(accession: PfamID) throws -> Family? {
        try query("SELECT \(Self.familyColumns) FROM family WHERE accession = ?",
                  bind: { Self.bindText($0, 1, accession.rawValue) },
                  row: Self.family).first
    }

    public func families(rows: [Int]) throws -> [Family] {
        guard !rows.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: rows.count).joined(separator: ",")
        let found = try query(
            "SELECT \(Self.familyColumns) FROM family WHERE row IN (\(placeholders))",
            bind: { statement in
                for (offset, row) in rows.enumerated() {
                    sqlite3_bind_int(statement, Int32(offset + 1), Int32(row))
                }
            },
            row: Self.family
        )
        // Preserve the caller's ordering: these arrive ranked by similarity and
        // SQL is under no obligation to hand them back that way.
        let byRow = Dictionary(uniqueKeysWithValues: found.map { ($0.row, $0) })
        return rows.compactMap { byRow[$0] }
    }

    /// All families, ordered by row, for the Galaxy's point cloud.
    public func allFamilies() throws -> [Family] {
        try query("SELECT \(Self.familyColumns) FROM family ORDER BY row", row: Self.family)
    }

    public func families(inClan clan: ClanID) throws -> [Family] {
        try query("""
            SELECT \(Self.familyColumns) FROM family
            WHERE clan = ? ORDER BY n_proteins DESC
            """,
            bind: { Self.bindText($0, 1, clan.rawValue) },
            row: Self.family)
    }

    /// Domains of unknown function, largest first: the Prospector's whole list.
    public func unknownFunctionFamilies(limit: Int = 500, offset: Int = 0) throws -> [Family] {
        try query("""
            SELECT \(Self.familyColumns) FROM family
            WHERE is_duf = 1 ORDER BY n_proteins DESC, row LIMIT ? OFFSET ?
            """,
            bind: {
                sqlite3_bind_int($0, 1, Int32(limit))
                sqlite3_bind_int($0, 2, Int32(offset))
            },
            row: Self.family)
    }

    // MARK: - Clans

    public func clan(_ accession: ClanID) throws -> Clan? {
        try query("SELECT accession, identifier, description, hue, n_families FROM clan WHERE accession = ?",
                  bind: { Self.bindText($0, 1, accession.rawValue) },
                  row: Self.clan).first
    }

    public func allClans() throws -> [Clan] {
        try query("""
            SELECT accession, identifier, description, hue, n_families
            FROM clan ORDER BY n_families DESC
            """, row: Self.clan)
    }

    private static func clan(from s: OpaquePointer) -> Clan {
        Clan(
            accession: ClanID(text(s, 0) ?? ""),
            identifier: text(s, 1),
            summary: text(s, 2),
            hue: sqlite3_column_double(s, 3),
            familyCount: Int(sqlite3_column_int(s, 4))
        )
    }

    // MARK: - Architectures

    public func architectures(forFamilyRow row: Int, limit: Int = 12) throws -> [Architecture] {
        let ids = try query("""
            SELECT architecture_id FROM family_architecture
            WHERE family_row = ? ORDER BY rank LIMIT ?
            """,
            bind: {
                sqlite3_bind_int($0, 1, Int32(row))
                sqlite3_bind_int($0, 2, Int32(limit))
            },
            row: { Int(sqlite3_column_int($0, 0)) })
        return try architectures(ids: ids)
    }

    public func architectures(ids: [Int]) throws -> [Architecture] {
        guard !ids.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: ids.count).joined(separator: ",")
        let bindIDs: (OpaquePointer) -> Void = { statement in
            for (offset, id) in ids.enumerated() {
                sqlite3_bind_int(statement, Int32(offset + 1), Int32(id))
            }
        }

        var membersByArchitecture: [Int: [(Int, PfamID)]] = [:]
        _ = try query("""
            SELECT m.architecture_id, m.position, f.accession
            FROM architecture_member m
            JOIN family f ON f.row = m.family_row
            WHERE m.architecture_id IN (\(placeholders))
            ORDER BY m.architecture_id, m.position
            """,
            bind: bindIDs,
            row: { s -> Void in
                let id = Int(sqlite3_column_int(s, 0))
                let position = Int(sqlite3_column_int(s, 1))
                let accession = PfamID(Self.text(s, 2) ?? "")
                membersByArchitecture[id, default: []].append((position, accession))
            })

        let rows = try query("""
            SELECT id, signature, n_proteins, rep_uniprot, rep_length
            FROM architecture WHERE id IN (\(placeholders))
            """,
            bind: bindIDs,
            row: { s in
                let id = Int(sqlite3_column_int(s, 0))
                return Architecture(
                    id: id,
                    signature: Self.text(s, 1) ?? "",
                    members: (membersByArchitecture[id] ?? [])
                        .sorted { $0.0 < $1.0 }.map(\.1),
                    proteinCount: Int(sqlite3_column_int(s, 2)),
                    representativeUniProt: Self.text(s, 3),
                    representativeLength: sqlite3_column_type(s, 4) == SQLITE_NULL
                        ? nil : Int(sqlite3_column_int(s, 4))
                )
            })

        let byID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })
        return ids.compactMap { byID[$0] }
    }

    /// Architectures containing every one of `members`, commonest first.
    /// This is what "what proteins are built like mine?" resolves to.
    public func architectures(containing members: [PfamID], limit: Int = 40) throws -> [Architecture] {
        guard !members.isEmpty else { return [] }
        let placeholders = Array(repeating: "?", count: members.count).joined(separator: ",")
        let ids = try query("""
            SELECT m.architecture_id
            FROM architecture_member m
            JOIN family f ON f.row = m.family_row
            WHERE f.accession IN (\(placeholders))
            GROUP BY m.architecture_id
            HAVING COUNT(DISTINCT f.accession) = ?
            ORDER BY (SELECT n_proteins FROM architecture a WHERE a.id = m.architecture_id) DESC
            LIMIT ?
            """,
            bind: { statement in
                for (offset, member) in members.enumerated() {
                    Self.bindText(statement, Int32(offset + 1), member.rawValue)
                }
                sqlite3_bind_int(statement, Int32(members.count + 1), Int32(members.count))
                sqlite3_bind_int(statement, Int32(members.count + 2), Int32(limit))
            },
            row: { Int(sqlite3_column_int($0, 0)) })
        return try architectures(ids: ids)
    }

    public func cooccurrence(forFamilyRow row: Int, limit: Int = 16) throws -> [CooccurrenceEdge] {
        try query("""
            SELECT family_row, partner_row, n_proteins, n_before, n_after
            FROM cooccurrence WHERE family_row = ?
            ORDER BY n_proteins DESC LIMIT ?
            """,
            bind: {
                sqlite3_bind_int($0, 1, Int32(row))
                sqlite3_bind_int($0, 2, Int32(limit))
            },
            row: { s in
                CooccurrenceEdge(
                    familyRow: Int(sqlite3_column_int(s, 0)),
                    partnerRow: Int(sqlite3_column_int(s, 1)),
                    proteinCount: Int(sqlite3_column_int(s, 2)),
                    countBefore: Int(sqlite3_column_int(s, 3)),
                    countAfter: Int(sqlite3_column_int(s, 4))
                )
            })
    }

    // MARK: - Text search

    /// Literal search over identifier, summary and abstract.
    ///
    /// This runs alongside the semantic search rather than instead of it: FTS
    /// finds "Peptidase_S8" and an accession, the embedding finds "breaks down
    /// plastic". Neither alone covers what people type.
    public func search(text: String, limit: Int = 50) throws -> [Family] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // An accession is an exact request, not a ranking problem. Left to
        // bm25, "PF00069" came back behind a family whose abstract happened to
        // cite it, which is the wrong answer to an unambiguous question.
        if let exact = try exactAccession(trimmed) {
            let rest = try ftsSearch(trimmed, limit: limit)
            return [exact] + rest.filter { $0.accession != exact.accession }
        }
        return try ftsSearch(trimmed, limit: limit)
    }

    private func exactAccession(_ text: String) throws -> Family? {
        let candidate = text.uppercased()
        guard candidate.hasPrefix("PF"), candidate.count >= 7,
              candidate.dropFirst(2).allSatisfy(\.isNumber) else { return nil }
        return try family(accession: PfamID(candidate))
    }

    private func ftsSearch(_ trimmed: String, limit: Int) throws -> [Family] {

        // Quote every term so punctuation in a query cannot become FTS syntax,
        // and suffix the last one so search-as-you-type matches prefixes.
        let terms = trimmed
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map { "\"\($0)\"" }
        guard var expression = terms.last else { return [] }
        expression += "*"
        let full = (terms.dropLast() + [expression]).joined(separator: " ")

        return try query("""
            SELECT \(Self.familyColumns.split(separator: ",")
                        .map { "f." + $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .joined(separator: ", "))
            FROM family_fts
            JOIN family f ON f.row = family_fts.rowid
            WHERE family_fts MATCH ?
            ORDER BY bm25(family_fts, 20.0, 10.0, 4.0, 1.0)
            LIMIT ?
            """,
            bind: {
                Self.bindText($0, 1, full)
                sqlite3_bind_int($0, 2, Int32(limit))
            },
            row: Self.family)
    }

    // MARK: - Metadata

    public func meta() throws -> [String: String] {
        let pairs = try query("SELECT key, value FROM meta") { s in
            (Self.text(s, 0) ?? "", Self.text(s, 1) ?? "")
        }
        return Dictionary(uniqueKeysWithValues: pairs)
    }
}
