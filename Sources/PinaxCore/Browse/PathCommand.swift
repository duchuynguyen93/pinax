import Foundation

/// Lệnh gõ ở ô đường dẫn (⌘L), kiểu `code .`. Thuần phân tích chuỗi: KHÔNG chạy shell, chỉ mô tả "mở thư mục bằng app nào".
public struct PathCommand: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        /// Bundle id theo thứ tự ưu tiên; dùng id đầu tiên có cài.
        case apps([String])
        /// Terminal đã chọn trong Settings.
        case terminal
        case finder
    }

    /// Tên lệnh đã chuẩn hoá (lowercase).
    public let name: String
    public let target: Target
    /// nil hoặc "." = thư mục đang xem.
    public let argument: String?

    public static let known: [(name: String, target: Target)] = [
        ("code", .apps(["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"])),
        ("cursor", .apps(["com.todesktop.230313mzl4w4u92"])),
        ("zed", .apps(["dev.zed.Zed", "dev.zed.Zed-Preview"])),
        ("subl", .apps(["com.sublimetext.4", "com.sublimetext.3"])),
        ("xed", .apps(["com.apple.dt.Xcode"])),
        ("xcode", .apps(["com.apple.dt.Xcode"])),
        ("nova", .apps(["com.panic.Nova"])),
        ("bbedit", .apps(["com.barebones.bbedit"])),
        ("idea", .apps(["com.jetbrains.intellij", "com.jetbrains.intellij.ce"])),
        ("pycharm", .apps(["com.jetbrains.pycharm", "com.jetbrains.pycharm.ce"])),
        ("webstorm", .apps(["com.jetbrains.WebStorm"])),
        ("studio", .apps(["com.google.android.studio"])),
        ("fork", .apps(["com.DanPristupov.Fork"])),
        ("tower", .apps(["com.fournova.Tower3"])),
        ("term", .terminal),
        ("terminal", .terminal),
        ("iterm", .apps(["com.googlecode.iterm2"])),
        ("warp", .apps(["dev.warp.Warp-Stable"])),
        ("ghostty", .apps(["com.mitchellh.ghostty"])),
        ("finder", .finder),
    ]

    /// Có tiền tố ">" → ép là lệnh (không đối số cũng được). Không có ">" → chỉ nhận khi từ đầu là lệnh đã biết
    /// VÀ có đối số không rỗng (để thư mục tên "zed" vẫn đi được như đường dẫn).
    public static func parse(_ text: String) -> PathCommand? {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let forced = s.hasPrefix(">")
        if forced {
            s = String(s.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !s.isEmpty else { return nil }
        let word: String
        let rest: String
        if let sp = s.firstIndex(where: \.isWhitespace) {
            word = String(s[..<sp])
            rest = String(s[sp...]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            word = s
            rest = ""
        }
        let name = word.lowercased()
        guard let entry = known.first(where: { $0.name == name }) else { return nil }
        if !forced && rest.isEmpty { return nil }
        return PathCommand(name: name, target: entry.target, argument: rest.isEmpty ? nil : rest)
    }

    /// Hoàn thành tên lệnh cho Tab khi text bắt đầu ">": tên khớp tiền tố, đã sắp. Đã gõ qua tên lệnh (có khoảng trắng) → [].
    public static func completions(_ text: String) -> [String] {
        let s = text.drop(while: \.isWhitespace)
        guard s.hasPrefix(">") else { return [] }
        let typed = s.dropFirst().drop(while: \.isWhitespace)
        guard !typed.contains(where: \.isWhitespace) else { return [] }
        let prefix = typed.lowercased()
        return known.map(\.name).filter { $0.hasPrefix(prefix) }.sorted()
    }
}
