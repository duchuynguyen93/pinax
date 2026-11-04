import Foundation

public struct Candidate: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    /// Allocated size.
    public let size: Int64
    public let fingerprint: FileFingerprint
    /// Lý do dạng tiếng Anh (fallback). UI nên localize từ `reasonKind`.
    public let reason: String
    /// Lý do có cấu trúc để UI tự localize (core không có localization).
    public let reasonKind: ReasonKind
    public let lastUsed: Date?
    public var preselected: Bool

    public init(id: UUID = UUID(), url: URL, size: Int64, fingerprint: FileFingerprint,
                reason: String, reasonKind: ReasonKind = .other, lastUsed: Date?, preselected: Bool) {
        self.id = id
        self.url = url
        self.size = size
        self.fingerprint = fingerprint
        self.reason = reason
        self.reasonKind = reasonKind
        self.lastUsed = lastUsed
        self.preselected = preselected
    }
}

/// Lý do một candidate bị đề xuất, dạng dữ liệu để UI localize.
public enum ReasonKind: Hashable, Sendable {
    /// Installer của app đã cài (tên app).
    case installedApp(String)
    /// Bản trùng; associated value = bản được giữ lại.
    case duplicateOf(URL)
    /// App lâu không mở; associated value = lần mở cuối.
    case lastUsed(Date)
    /// Cũ hơn N ngày.
    case olderThan(days: Int)
    /// Cache công cụ dev (tên hiển thị).
    case devCache(String)
    /// node_modules của project lâu không đụng tới (tên project).
    case staleProject(String)
    case large
    case mailAttachment
    case screenRecording
    case other
}

public enum RuleStatus: Sendable {
    case ok
    case needsFullDiskAccess
    case failed(String)
}

public struct RuleResult: Sendable {
    public let ruleID: String
    public let candidates: [Candidate]
    public let status: RuleStatus

    public init(ruleID: String, candidates: [Candidate], status: RuleStatus) {
        self.ruleID = ruleID
        self.candidates = candidates
        self.status = status
    }
}
