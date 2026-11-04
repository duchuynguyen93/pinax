import Foundation

public protocol Trasher {
    /// Chuyển vào Thùng rác, trả về URL mới trong Thùng rác.
    func trash(_ url: URL) throws -> URL
}

public enum TrashError: Error, LocalizedError {
    case noResultingURL
    public var errorDescription: String? { "Trash returned no resulting URL" }
}

/// Bản thật: `FileManager.trashItem`. Đây là cách xoá duy nhất của app (§1.1).
public struct FileManagerTrasher: Trasher {
    public init() {}

    public func trash(_ url: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        if let resulting { return resulting as URL }
        // Hiếm: item đã vào Thùng rác nhưng hệ thống không trả URL. Đoán vị trí để vẫn hoàn tác được.
        let trashDir = FileManager.default.urls(for: .trashDirectory, in: .userDomainMask).first
        guard let trashDir else { throw TrashError.noResultingURL }
        return trashDir.appendingPathComponent(url.lastPathComponent)
    }
}
