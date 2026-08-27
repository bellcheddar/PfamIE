import Accelerate
import Foundation

/// A memory-mapped matrix of unit vectors with a fast matrix-vector product.
///
/// Two storage formats ship behind this: float16, and int8 with a per-row
/// scale. The manifest says which, so a re-forged release can change format
/// without a code change.
public protocol EmbeddingMatrix: AnyObject, Sendable {
    var rows: Int { get }
    var columns: Int { get }

    /// `self * vector`, one score per row. Rows and query are unit length, so
    /// the result is a cosine similarity and needs no normalising.
    func multiply(_ vector: [Float]) -> [Float]

    /// One row as float32. For single look-ups, never in a loop over the matrix.
    func row(_ index: Int) -> [Float]
}

public enum EmbeddingMatrixLoader {
    public enum LoadError: Error, CustomStringConvertible {
        case unknownFormat(String)

        public var description: String {
            switch self {
            case .unknownFormat(let dtype):
                return "The manifest describes a matrix format this build cannot read: \(dtype)."
            }
        }
    }

    /// Builds the right matrix for what the manifest says is on disk.
    public static func load(
        contentsOf url: URL, rows: Int, columns: Int, dtype: String
    ) throws -> any EmbeddingMatrix {
        switch dtype {
        case "int8+scale":
            return try Int8Matrix(contentsOf: url, rows: rows, columns: columns)
        case "float16":
            return try Float16Matrix(contentsOf: url, rows: rows, columns: columns)
        default:
            throw LoadError.unknownFormat(dtype)
        }
    }
}

/// Row-major int8 with a per-row float32 scale appended after the data.
///
/// Both shipped matrices hold L2-normalised vectors, so every value is in
/// [-1, 1] and a symmetric per-row scale costs almost nothing: measured on
/// 26,286 held-out sequences, int8 centroids score top-1 0.7150 against 0.7149
/// at float16, and the worst per-row round-trip cosine across both matrices is
/// 0.99990. It halves 41 MB of matrices to 21 MB.
///
/// The scale is applied to the *result* rather than to every element: the
/// product of a row and the query is linear in the row, so one vector multiply
/// over `rows` floats replaces `rows * columns` of them.
public final class Int8Matrix: EmbeddingMatrix, @unchecked Sendable {

    public let rows: Int
    public let columns: Int

    private let mapping: UnsafeRawPointer
    private let mappedBytes: Int
    private let values: UnsafePointer<Int8>
    private let scales: UnsafePointer<Float>

    private static let chunkRows = 8_192
    private let scratch: UnsafeMutablePointer<Float>
    private let lock = NSLock()

    public enum LoadError: Error, CustomStringConvertible {
        case unreadable(URL)
        case sizeMismatch(url: URL, expected: Int, found: Int)

        public var description: String {
            switch self {
            case .unreadable(let url):
                return "Could not map \(url.lastPathComponent)."
            case .sizeMismatch(let url, let expected, let found):
                return """
                \(url.lastPathComponent) is \(found) bytes but the manifest \
                describes \(expected). The bundled assets and the app are out of step.
                """
            }
        }
    }

    public init(contentsOf url: URL, rows: Int, columns: Int) throws {
        let dataBytes = rows * columns
        let scaleBytes = rows * MemoryLayout<Float>.size
        let expected = dataBytes + scaleBytes

        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { throw LoadError.unreadable(url) }
        defer { close(descriptor) }

        var status = stat()
        guard fstat(descriptor, &status) == 0 else { throw LoadError.unreadable(url) }
        let found = Int(status.st_size)
        guard found == expected else {
            throw LoadError.sizeMismatch(url: url, expected: expected, found: found)
        }

        guard let base = mmap(nil, expected, PROT_READ, MAP_PRIVATE, descriptor, 0),
              base != MAP_FAILED else {
            throw LoadError.unreadable(url)
        }

        self.rows = rows
        self.columns = columns
        self.mapping = UnsafeRawPointer(base)
        self.mappedBytes = expected
        self.values = self.mapping.assumingMemoryBound(to: Int8.self)
        self.scales = (self.mapping + dataBytes).assumingMemoryBound(to: Float.self)
        self.scratch = .allocate(capacity: Self.chunkRows * columns)
    }

    deinit {
        munmap(UnsafeMutableRawPointer(mutating: mapping), mappedBytes)
        scratch.deallocate()
    }

    public func multiply(_ vector: [Float]) -> [Float] {
        precondition(vector.count == columns,
                     "query has \(vector.count) dimensions, matrix has \(columns)")
        var out = [Float](repeating: 0, count: rows)

        lock.lock()
        defer { lock.unlock() }

        out.withUnsafeMutableBufferPointer { outBuffer in
            vector.withUnsafeBufferPointer { queryBuffer in
                var start = 0
                while start < rows {
                    let count = min(Self.chunkRows, rows - start)

                    vDSP_vflt8(values + start * columns, 1,
                               scratch, 1, vDSP_Length(count * columns))

                    cblas_sgemv(
                        CblasRowMajor, CblasNoTrans,
                        Int32(count), Int32(columns),
                        1.0,
                        scratch, Int32(columns),
                        queryBuffer.baseAddress!, 1,
                        0.0,
                        outBuffer.baseAddress! + start, 1
                    )

                    // Apply the per-row scale once per row, not once per value.
                    vDSP_vmul(outBuffer.baseAddress! + start, 1,
                              scales + start, 1,
                              outBuffer.baseAddress! + start, 1,
                              vDSP_Length(count))
                    start += count
                }
            }
        }
        return out
    }

    public func row(_ index: Int) -> [Float] {
        precondition(index >= 0 && index < rows, "row \(index) out of range")
        var out = [Float](repeating: 0, count: columns)
        out.withUnsafeMutableBufferPointer { buffer in
            vDSP_vflt8(values + index * columns, 1,
                       buffer.baseAddress!, 1, vDSP_Length(columns))
            var scale = scales[index]
            vDSP_vsmul(buffer.baseAddress!, 1, &scale,
                       buffer.baseAddress!, 1, vDSP_Length(columns))
        }
        return out
    }
}
