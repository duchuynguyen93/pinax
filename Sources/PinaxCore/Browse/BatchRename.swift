import Foundation

/// Kiểu đổi tên hàng loạt.
public enum RenameRule: Equatable, Sendable {
    case replace(find: String, with: String, caseSensitive: Bool, includeExtension: Bool)
    case add(text: String, atEnd: Bool)
    case format(base: String, start: Int, digits: Int, numberFirst: Bool, separator: String)
    case changeCase(CaseStyle, includeExtension: Bool)
    public enum CaseStyle: Sendable { case lower, upper, title }
}

/// Một dòng xem trước: tên cũ → tên mới kèm vấn đề (nếu có).
public struct RenameEntry: Equatable, Sendable {
    public let source: URL
    public let newName: String
    public let issue: Issue?
    public var target: URL { source.deletingLastPathComponent().appendingPathComponent(newName) }

    public init(source: URL, newName: String, issue: Issue?) {
        self.source = source
        self.newName = newName
        self.issue = issue
    }

    public enum Issue: Equatable, Sendable {
        /// Tên mới == tên cũ → bỏ qua, không phải lỗi.
        case unchanged
        /// `FileOps.validatedName` ném.
        case invalid(FileNameError)
        /// Hai mục cùng thư mục ra cùng tên (không phân biệt hoa/thường).
        case duplicateInBatch
        /// Đích đã có trên đĩa, không phải mục khác trong lượt (sẽ dời đi), không phải đổi hoa/thường của chính nó.
        case exists
    }
}

public enum BatchRename {
    // MARK: Tên mới

    /// Áp rule cho một tên (thuần). `index` bắt đầu từ 0 theo thứ tự `urls`.
    public static func newName(for url: URL, index: Int, count: Int, rule: RenameRule,
                               isPackage: Bool, isDirectory: Bool) -> String {
        let name = url.lastPathComponent
        // Thư mục thường: cả tên là stem. File / package: bỏ đuôi cuối.
        let (stem, ext) = (isDirectory && !isPackage) ? (name, "") : splitExtension(name)
        let dotExt = ext.isEmpty ? "" : "." + ext

        switch rule {
        case let .replace(find, with, caseSensitive, includeExtension):
            guard !find.isEmpty else { return name }
            let opts: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            func rep(_ s: String) -> String { s.replacingOccurrences(of: find, with: with, options: opts) }
            return includeExtension ? rep(name) : rep(stem) + dotExt

        case let .add(text, atEnd):
            return (atEnd ? stem + text : text + stem) + dotExt

        case let .format(base, start, digits, numberFirst, separator):
            var num = String(start + index)
            let pad = max(digits, 0)
            if num.count < pad { num = String(repeating: "0", count: pad - num.count) + num }
            let core: String
            if base.isEmpty { core = num }
            else { core = numberFirst ? num + separator + base : base + separator + num }
            return core + dotExt

        case let .changeCase(style, includeExtension):
            func conv(_ s: String) -> String {
                switch style {
                case .lower: return s.lowercased()
                case .upper: return s.uppercased()
                case .title: return titleCase(s)
                }
            }
            return includeExtension ? conv(name) : conv(stem) + dotExt
        }
    }

    /// Tách đuôi cuối. ".bashrc" và "abc." không có đuôi.
    static func splitExtension(_ name: String) -> (stem: String, ext: String) {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex,
              name.index(after: dot) != name.endIndex else { return (name, "") }
        return (String(name[..<dot]), String(name[name.index(after: dot)...]))
    }

    /// Viết hoa chữ đầu mỗi từ, phần còn lại viết thường; ranh giới từ: khoảng trắng, "-", "_".
    static func titleCase(_ s: String) -> String {
        var out = ""
        var atStart = true
        for ch in s {
            if ch.isWhitespace || ch == "-" || ch == "_" {
                out.append(ch); atStart = true
            } else {
                out += atStart ? String(ch).uppercased() : String(ch).lowercased()
                atStart = false
            }
        }
        return out
    }

    // MARK: Plan

    private static func nfc(_ s: String) -> String { s.precomposedStringWithCanonicalMapping }
    private static func key(_ s: String) -> String { nfc(s).lowercased() }

    private static func lstatInfo(_ path: String) -> stat? {
        var st = stat()
        return lstat(path, &st) == 0 ? st : nil
    }

    /// Dựng preview + kiểm tra (đọc đĩa: loại mục và lstat đích).
    public static func plan(_ urls: [URL], rule: RenameRule) -> [RenameEntry] {
        struct Draft { let url: URL; let name: String; var issue: RenameEntry.Issue? }
        var drafts: [Draft] = []
        drafts.reserveCapacity(urls.count)
        for (i, url) in urls.enumerated() {
            let rv = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
            let raw = newName(for: url, index: i, count: urls.count, rule: rule,
                              isPackage: rv?.isPackage ?? false, isDirectory: rv?.isDirectory ?? false)
            let old = url.lastPathComponent
            if nfc(raw) == nfc(old) {
                drafts.append(Draft(url: url, name: raw, issue: .unchanged)); continue
            }
            do {
                let valid = try FileOps.validatedName(raw)
                // Sau khi cắt khoảng trắng có thể trùng tên cũ.
                drafts.append(Draft(url: url, name: valid, issue: nfc(valid) == nfc(old) ? .unchanged : nil))
            } catch let e as FileNameError {
                drafts.append(Draft(url: url, name: raw, issue: .invalid(e)))
            } catch {
                drafts.append(Draft(url: url, name: raw, issue: .invalid(.empty)))
            }
        }

        func fullKey(_ url: URL, _ name: String) -> String {
            key(url.deletingLastPathComponent().path) + "/" + key(name)
        }

        // Trùng trong lượt: mục unchanged cũng giữ chỗ của tên nó.
        var counts: [String: Int] = [:]
        for d in drafts {
            if case .invalid = d.issue { continue }
            counts[fullKey(d.url, d.name), default: 0] += 1
        }
        // Nguồn sẽ dời đi (đổi tên thật).
        var leaving = Set<String>()
        for d in drafts where d.issue == nil { leaving.insert(key(d.url.path)) }

        var result: [RenameEntry] = []
        for d in drafts {
            var issue = d.issue
            if issue == nil {
                let target = d.url.deletingLastPathComponent().appendingPathComponent(d.name)
                if (counts[fullKey(d.url, d.name)] ?? 0) > 1 {
                    issue = .duplicateInBatch
                } else if let t = lstatInfo(target.path) {
                    let selfSame = lstatInfo(d.url.path).map { $0.st_dev == t.st_dev && $0.st_ino == t.st_ino } ?? false
                    if !selfSame && !leaving.contains(key(target.path)) { issue = .exists }
                }
            }
            result.append(RenameEntry(source: d.url, newName: d.name, issue: issue))
        }
        return result
    }

    /// Thực hiện được: không mục nào có issue khác `.unchanged`, và ít nhất một mục đổi.
    public static func canApply(_ entries: [RenameEntry]) -> Bool {
        var changed = false
        for e in entries {
            switch e.issue {
            case nil: changed = true
            case .unchanged?: continue
            default: return false
            }
        }
        return changed
    }

    // MARK: Moves

    /// Tên tạm; bỏ phần tên cũ nếu tổng vượt 255 byte (giới hạn tên của APFS / HFS+).
    static func tempName(hex: String, old: String) -> String {
        let full = ".pinax-rename-\(hex)-\(old)"
        return full.utf8.count <= 255 ? full : ".pinax-rename-\(hex)"
    }

    /// Thứ tự move an toàn. Bỏ mục `.unchanged`. Chiến lược: nếu có BẤT KỲ va chạm (đích của mục này
    /// trùng không phân biệt hoa/thường với nguồn của mục khác trong lượt, vd hoán đổi / chuỗi), mọi mục
    /// cần đổi đi hai bước qua tên tạm `.pinax-rename-<8hex>-<tên cũ>` cùng thư mục: mọi bước 1, rồi mọi bước 2.
    /// Không va chạm → một bước.
    public static func moves(_ entries: [RenameEntry]) -> [(from: URL, to: URL)] {
        let active = entries.filter { $0.issue == nil }
        let sources = active.map { key($0.source.path) }
        var collision = false
        for (i, e) in active.enumerated() {
            let t = key(e.target.path)
            if sources.enumerated().contains(where: { $0.offset != i && $0.element == t }) { collision = true; break }
        }
        guard collision else { return active.map { (from: $0.source, to: $0.target) } }

        var step1: [(from: URL, to: URL)] = []
        var step2: [(from: URL, to: URL)] = []
        for e in active {
            let hex = String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8)).lowercased()
            let tmp = e.source.deletingLastPathComponent()
                .appendingPathComponent(tempName(hex: hex, old: e.source.lastPathComponent))
            step1.append((from: e.source, to: tmp))
            step2.append((from: tmp, to: e.target))
        }
        return step1 + step2
    }
}
