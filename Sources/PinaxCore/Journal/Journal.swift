import Foundation

public enum JournalOp: Codable, Equatable, Sendable {
    case trash(original: URL, trashed: URL)
    case move(from: URL, to: URL)
    case createDir(URL)
}

public struct Batch: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let title: String
    public var ops: [JournalOp]
    public var undone: Bool

    public init(id: UUID = UUID(), date: Date = Date(), title: String, ops: [JournalOp], undone: Bool = false) {
        self.id = id
        self.date = date
        self.title = title
        self.ops = ops
        self.undone = undone
    }
}

/// Lý do bỏ qua một item; UI tự localize.
public enum SkipReason: String, Equatable, Sendable {
    /// Không còn tồn tại / nguồn đã mất.
    case missing
    /// Fingerprint khác lúc quét: "đã thay đổi từ lúc quét".
    case changedSinceScan
    /// PathGuard từ chối.
    case protectedPath
    /// Candidate là symlink (không bao giờ theo symlink).
    case symlink
    /// Đích (Tidy) đã tồn tại, không ghi đè.
    case destinationExists
    /// Undo: chỗ cũ đã có file.
    case originalOccupied
    /// Undo createDir: thư mục không rỗng.
    case directoryNotEmpty
}

public enum ItemStatus: Equatable, Sendable {
    case done
    case skipped(SkipReason)
    case failed(String)
}

public struct ItemOutcome: Equatable, Sendable {
    public let url: URL
    public let status: ItemStatus

    public init(url: URL, status: ItemStatus) {
        self.url = url
        self.status = status
    }
}

public struct PerformResult: Sendable {
    public let outcomes: [ItemOutcome]
    /// nil nếu không có op nào thành công (không ghi batch rỗng).
    public let batch: Batch?
    /// Lỗi ghi journal (nếu có); thao tác file đã xảy ra rồi nên không ném.
    public let journalError: String?
}
