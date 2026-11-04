import Foundation

public enum SizeCalculator {
    private static let keys: [URLResourceKey] = [
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isSymbolicLinkKey, .isRegularFileKey,
    ]

    /// Tổng allocated size. Không theo symlink (symlink tính 0). Ném `CancellationError` nếu task bị huỷ.
    public static func allocatedSize(of url: URL) throws -> Int64 {
        let fm = FileManager.default
        var url = url
        url.removeAllCachedResourceValues()
        let keySet = Set(keys)
        guard let rootValues = try? url.resourceValues(forKeys: keySet) else { return 0 }
        if rootValues.isSymbolicLink == true { return 0 }
        var total = fileSize(rootValues)
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                             options: [], errorHandler: { _, _ in true }) else {
            return total
        }
        for case let item as URL in enumerator {
            try Task.checkCancellation()
            guard let values = try? item.resourceValues(forKeys: keySet) else { continue }
            if values.isSymbolicLink == true { continue }
            total += fileSize(values)
        }
        return total
    }

    private static func fileSize(_ v: URLResourceValues) -> Int64 {
        Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
    }
}
