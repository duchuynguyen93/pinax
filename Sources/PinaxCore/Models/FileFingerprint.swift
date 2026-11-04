import Foundation

/// Dấu vân tay lúc quét; so lại ngay trước khi thao tác (§1.2).
public struct FileFingerprint: Codable, Hashable, Sendable {
    public let size: Int64
    public let modified: Date

    public init(size: Int64, modified: Date) {
        self.size = size
        self.modified = modified
    }

    /// Đọc từ resource values. Không theo symlink. Thư mục không có `fileSize` → 0.
    /// Trả nil nếu không đọc được (không tồn tại, không có quyền).
    public static func read(from url: URL) -> FileFingerprint? {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        // URL cache resource values theo instance: bắt buộc xoá cache, nếu không sẽ đọc lại giá trị cũ lúc quét.
        var fresh = url
        fresh.removeAllCachedResourceValues()
        guard let values = try? fresh.resourceValues(forKeys: keys),
              let modified = values.contentModificationDate else { return nil }
        return FileFingerprint(size: Int64(values.fileSize ?? 0), modified: modified)
    }

    /// So khớp (dung sai 1 ms cho sai số làm tròn thời gian).
    public func matches(_ other: FileFingerprint) -> Bool {
        size == other.size && abs(modified.timeIntervalSince(other.modified)) < 0.001
    }
}
