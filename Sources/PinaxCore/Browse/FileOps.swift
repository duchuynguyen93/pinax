import Foundation

/// Tên mới không hợp lệ khi đổi tên.
public enum FileNameError: Error, Equatable, Sendable {
    case empty
    case containsSeparator
    case reserved
    case tooLong
    /// Tên mới trùng tên hiện tại.
    case unchanged
}

/// Thao tác file tối thiểu của trình duyệt, mỏng trên `Executor` (PathGuard + journal + hoàn tác).
public struct FileOps {
    public let executor: Executor
    public let home: URL
    public let trasher: Trasher

    public init(executor: Executor, home: URL, trasher: Trasher = FileManagerTrasher()) {
        self.executor = executor
        self.home = home
        self.trasher = trasher
    }

    // MARK: Rename

    /// Cắt khoảng trắng đầu/cuối rồi kiểm tra. Trả tên đã chuẩn hoá.
    public static func validatedName(_ raw: String) throws -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { throw FileNameError.empty }
        if name.contains("/") || name.contains(":") { throw FileNameError.containsSeparator }
        if name == "." || name == ".." { throw FileNameError.reserved }
        if name.utf8.count > 255 { throw FileNameError.tooLong }
        return name
    }

    /// Đổi tên = `.move(from, to)`; không bao giờ ghi đè (đích tồn tại → outcome `.skipped(.destinationExists)`).
    public func rename(_ url: URL, to newName: String, title: String = "Rename") throws -> PerformResult {
        let name = try Self.validatedName(newName)
        if name == url.lastPathComponent { throw FileNameError.unchanged }
        let dest = url.deletingLastPathComponent().appendingPathComponent(name)
        return executor.perform(moves: [(from: url, to: dest)], createDirs: [], title: title, home: home)
    }

    /// Đổi tên cả lượt thành một batch journal (⌘Z trả lại hết, kể cả bước tạm).
    public func batchRename(_ entries: [RenameEntry], title: String) -> PerformResult {
        executor.perform(moves: BatchRename.moves(entries), createDirs: [], title: title, home: home)
    }

    // MARK: New folder

    /// `untitled folder`, `untitled folder 2`, … (so tên không phân biệt hoa/thường).
    public static func availableFolderName(in dir: URL, base: String = "untitled folder") -> String {
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).map { $0.lowercased() })
        if !existing.contains(base.lowercased()) { return base }
        var n = 2
        while existing.contains("\(base) \(n)".lowercased()) { n += 1 }
        return "\(base) \(n)"
    }

    /// Tạo thư mục mới (`.createDir`). `outcomes.first?.url` là thư mục vừa tạo.
    public func newFolder(in dir: URL, title: String = "New folder") -> PerformResult {
        let target = dir.appendingPathComponent(Self.availableFolderName(in: dir), isDirectory: true)
        return executor.perform(moves: [], createDirs: [target], title: title, home: home)
    }

    // MARK: Trash

    /// Chuyển vào Thùng rác qua `Executor.perform(candidates:)`; fingerprint đọc ngay lúc gọi.
    public func trash(items: [URL], title: String = "Move to Trash") -> PerformResult {
        var candidates: [Candidate] = []
        var missing: [ItemOutcome] = []
        for url in items {
            guard let fp = FileFingerprint.read(from: url) else {
                missing.append(.init(url: url, status: .skipped(.missing))); continue
            }
            candidates.append(Candidate(url: url, size: fp.size, fingerprint: fp, reason: "Browser",
                                        reasonKind: .other, lastUsed: nil, preselected: true))
        }
        let r = executor.perform(candidates: candidates, title: title, trasher: trasher, home: home)
        guard !missing.isEmpty else { return r }
        return PerformResult(outcomes: missing + r.outcomes, batch: r.batch, journalError: r.journalError)
    }
}
