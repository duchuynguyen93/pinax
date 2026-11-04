import Foundation

/// Phần tên được chọn sẵn khi bắt đầu đổi tên tại chỗ (như Finder: bỏ phần đuôi file).
public enum FileNameSelection {
    /// Độ dài (UTF-16, dùng cho `NSRange`) phần cần chọn. Thư mục / package: cả tên.
    /// File: bỏ đuôi cuối cùng; tên không có đuôi, file ẩn kiểu `.gitignore` hoặc tên kết thúc bằng `.` thì chọn cả tên.
    public static func length(of name: String, stripExtension: Bool) -> Int {
        let whole = name.utf16.count
        guard stripExtension, let dot = name.lastIndex(of: "."),
              dot != name.startIndex, name.index(after: dot) != name.endIndex else { return whole }
        return name[..<dot].utf16.count
    }
}

/// Thứ tự menu "Open With": app mặc định trước, rồi các app khác theo tên.
public enum OpenWithOrdering {
    public struct Entry: Equatable, Sendable {
        public let url: URL
        public let name: String
        public let isDefault: Bool
    }

    /// Bỏ trùng theo đường dẫn; app mặc định luôn có mặt (kể cả khi không nằm trong `apps`).
    public static func order(apps: [URL], defaultApp: URL?, name: (URL) -> String) -> [Entry] {
        var seen = Set<String>()
        var entries: [Entry] = []
        if let d = defaultApp {
            seen.insert(d.path)
            entries.append(Entry(url: d, name: name(d), isDefault: true))
        }
        let others = apps.filter { seen.insert($0.path).inserted }
            .map { Entry(url: $0, name: name($0), isDefault: false) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return entries + others
    }
}

/// Các nhóm thay đổi hiện trong tooltip của git ở path bar.
public enum GitChangeKind: Sendable, Equatable { case conflicted, staged, modified, untracked }

extension GitSummary {
    /// Số file có thay đổi (mỗi file một lần).
    public var totalChanges: Int { changedFiles }

    /// Các nhóm khác 0, theo thứ tự conflicted, staged, modified, untracked.
    public var changeBreakdown: [(kind: GitChangeKind, count: Int)] {
        [(GitChangeKind.conflicted, conflicted), (.staged, staged), (.modified, modified), (.untracked, untracked)]
            .filter { $0.1 > 0 }.map { (kind: $0.0, count: $0.1) }
    }

    /// "↑2 ↓1"; bỏ phần bằng 0; nil khi cả hai đều 0.
    public var aheadBehindLabel: String? {
        let parts = [ahead > 0 ? "↑\(ahead)" : nil, behind > 0 ? "↓\(behind)" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

extension FileOps {
    /// Thao tác ghi lên `url` (đổi tên / chuyển Thùng rác) có qua được PathGuard không. Chỉ để bật/tắt menu;
    /// `Executor` vẫn kiểm lại lúc thực hiện.
    public func canModify(_ url: URL) -> Bool { executor.makeGuard(home: home).isAllowed(url) }

    /// Tạo thư mục mới trong `dir` có được phép không.
    public func canCreateFolder(in dir: URL) -> Bool {
        canModify(dir.appendingPathComponent(Self.availableFolderName(in: dir), isDirectory: true))
    }
}
