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

    /// Tiền tố chung dài nhất (không phân biệt hoa/thường, lấy dạng chữ của phần tử đầu).
    public static func commonPrefix(_ list: [String]) -> String {
        guard let first = list.first else { return "" }
        var prefix = Substring(first)
        for s in list.dropFirst() {
            while !prefix.isEmpty, !s.lowercased().hasPrefix(prefix.lowercased()) { prefix = prefix.dropLast() }
        }
        return String(prefix)
    }

    /// Kết quả một lần bấm Tab / ⇧Tab trên `text`.
    public struct Step: Equatable, Sendable {
        public var text: String
        public var matches: [String]
        /// Chỉ số đang chọn trong `matches` khi đang xoay vòng; nil nếu mới điền tiền tố chung / duy nhất.
        public var index: Int?
    }

    /// Áp dụng Tab. `cycle` là trạng thái xoay vòng của lần bấm trước (nếu `text` vẫn là mục đang chọn thì chuyển mục).
    /// Trả nil nếu không có gợi ý nào. Giữ nguyên dạng `~` người dùng gõ.
    public static func step(text: String, home: URL, cycle: (matches: [String], index: Int)?, backwards: Bool = false) -> Step? {
        if let c = cycle, c.matches.indices.contains(c.index), c.matches[c.index] == text {
            let n = c.matches.count
            let next = (c.index + (backwards ? n - 1 : 1)) % n
            return Step(text: c.matches[next], matches: c.matches, index: next)
        }
        let matches = complete(text, home: home)
        guard !matches.isEmpty else { return nil }
        if matches.count == 1 { return Step(text: matches[0], matches: [], index: nil) }
        let common = commonPrefix(matches)
        if common.count > text.count { return Step(text: common, matches: matches, index: nil) }
        let start = backwards ? matches.count - 1 : 0
        return Step(text: matches[start], matches: matches, index: start)
    }
}
