import Foundation
import CryptoKit

enum FileHasher {
    /// SHA-256 stream theo chunk 1 MB. `limit` = chỉ băm N byte đầu. Ném `CancellationError` nếu task bị huỷ.
    static func sha256(of url: URL, limit: Int? = nil) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            try Task.checkCancellation()
            let chunkSize = min(1 << 20, remaining)
            guard let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty else { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        return Data(hasher.finalize())
    }
}
