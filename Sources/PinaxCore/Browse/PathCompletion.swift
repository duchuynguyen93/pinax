import Foundation

/// Gợi ý hoàn thành đường dẫn khi gõ ở ⌘L. Chỉ thư mục, không phân biệt hoa/thường.
public enum PathCompletion {
    public static let maxResults = 50

    /// Trả về đường dẫn đầy đủ (giữ nguyên dạng người dùng gõ, `~` không bị mở rộng) kết thúc bằng `/`.
    /// Chỉ nhận đường dẫn tuyệt đối hoặc bắt đầu bằng `~`; còn lại trả `[]`.
    public static func complete(_ typed: String, home: URL) -> [String] {
        if typed == "~" { return ["~/"] }
        guard typed.hasPrefix("/") || typed.hasPrefix("~/") else { return [] }

        let slash = typed.lastIndex(of: "/")!
        let typedParent = String(typed[...slash])      // "~/Doc/" → "~/"
        let prefix = String(typed[typed.index(after: slash)...])
        let parentPath = typedParent.hasPrefix("~/")
            ? home.path + "/" + typedParent.dropFirst(2)
            : typedParent

        let parent = URL(fileURLWithPath: parentPath, isDirectory: true)
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: parent.path) else { return [] }

        let wantsHidden = prefix.hasPrefix(".")
        var matches: [String] = []
        for name in names {
            if name.hasPrefix(".") && !wantsHidden { continue }
            if !prefix.isEmpty && !name.lowercased().hasPrefix(prefix.lowercased()) { continue }
            var isDir: ObjCBool = false // theo cả symlink trỏ tới thư mục
            guard FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path,
                                                 isDirectory: &isDir), isDir.boolValue else { continue }
            matches.append(name)
        }
        matches.sort { $0.localizedStandardCompare($1) == .orderedAscending }
        return matches.prefix(maxResults).map { typedParent + $0 + "/" }
    }
}
