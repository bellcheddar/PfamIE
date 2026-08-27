import Accelerate
import Foundation

/// A memory-mapped, row-major float16 matrix with a fast matrix-vector product.
///
/// Both shipped matrices (30,031 x 320 centroids and 30,031 x 384 description
/// embeddings) are float16 on disk, which costs nothing that matters: the worst
/// cosine between a float32 centroid and its float16 round trip is 0.9999998.
///
/// The product converts to float32 in chunks rather than holding a float32 copy
/// of the whole matrix. A resident copy of both matrices would be 84 MB on a
/// phone; chunking keeps it to the mapped pages plus one reusable scratch
/// buffer, and the conversion is memory-bandwidth bound either way.
public final class Float16Matrix: @unchecked Sendable {

    public let rows: Int
    public let columns: Int

    private let mapping: UnsafeRawPointer
    private let mappedBytes: Int
    private let values: UnsafePointer<UInt16>

    /// Rows converted per chunk. 8,192 x 384 floats is a 12 MB scratch buffer,
    /// comfortably inside L2 on the devices this ships to.
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
        let expected = rows * columns * MemoryLayout<UInt16>.size

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
        self.values = self.mapping.assumingMemoryBound(to: UInt16.self)
        self.scratch = .allocate(capacity: Self.chunkRows * columns)
    }

    deinit {
        munmap(UnsafeMutableRawPointer(mutating: mapping), mappedBytes)
        scratch.deallocate()
    }

    /// Returns `self * vector`, one score per row.
    ///
    /// Both the rows and the query are unit length, so the result is a cosine
    /// similarity directly and nothing needs normalising afterwards.
    public func multiply(_ vector: [Float]) -> [Float] {
        precondition(vector.count == columns, "query has \(vector.count) dimensions, matrix has \(columns)")

        var out = [Float](repeating: 0, count: rows)

        lock.lock()
        defer { lock.unlock() }

        out.withUnsafeMutableBufferPointer { outBuffer in
            vector.withUnsafeBufferPointer { queryBuffer in
                var start = 0
                while start < rows {
                    let count = min(Self.chunkRows, rows - start)
                    convert(rowOffset: start, rowCount: count)

                    cblas_sgemv(
                        CblasRowMajor, CblasNoTrans,
                        Int32(count), Int32(columns),
                        1.0,
                        scratch, Int32(columns),
                        queryBuffer.baseAddress!, 1,
                        0.0,
                        outBuffer.baseAddress! + start, 1
                    )
                    start += count
                }
            }
        }
        return out
    }

    /// Copies one row out as float32. Used for single-family look-ups, never in
    /// a loop over the whole matrix.
    public func row(_ index: Int) -> [Float] {
        precondition(index >= 0 && index < rows, "row \(index) out of range")
        var out = [Float](repeating: 0, count: columns)
        var source = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: values + index * columns),
            height: 1, width: vImagePixelCount(columns),
            rowBytes: columns * MemoryLayout<UInt16>.size
        )
        out.withUnsafeMutableBufferPointer { buffer in
            var destination = vImage_Buffer(
                data: buffer.baseAddress,
                height: 1, width: vImagePixelCount(columns),
                rowBytes: columns * MemoryLayout<Float>.size
            )
            _ = vImageConvert_Planar16FtoPlanarF(&source, &destination, 0)
        }
        return out
    }

    private func convert(rowOffset: Int, rowCount: Int) {
        var source = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: values + rowOffset * columns),
            height: vImagePixelCount(rowCount),
            width: vImagePixelCount(columns),
            rowBytes: columns * MemoryLayout<UInt16>.size
        )
        var destination = vImage_Buffer(
            data: scratch,
            height: vImagePixelCount(rowCount),
            width: vImagePixelCount(columns),
            rowBytes: columns * MemoryLayout<Float>.size
        )
        _ = vImageConvert_Planar16FtoPlanarF(&source, &destination, 0)
    }
}
