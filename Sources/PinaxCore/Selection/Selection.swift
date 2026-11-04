import Foundation

/// Các hàm thuần để làm sạch tập candidate người dùng đã tick, trước khi tính tổng / chuyển vào Thùng rác.
public enum Selection {
    /// Thành phần đường dẫn đã resolve + chuẩn hoá, lowercased (APFS mặc định không phân biệt hoa thường;
    /// so sánh theo hướng thận trọng để không bỏ sót lồng nhau).
    static func components(_ url: URL) -> [String] {
        url.resolvingSymlinksInPath().standardizedFileURL.pathComponents.map { $0.lowercased() }
    }

    /// Bỏ candidate nằm trong path của một candidate khác cũng được chọn (cha đã bao trùm),
    /// và gộp các candidate trùng path. Giữ nguyên thứ tự gốc. O(n · độ sâu path).
    public static func effectiveSelection(_ selected: [Candidate]) -> [Candidate] {
        let comps = selected.map { components($0.url) }
        let all = Set(comps)
        var result: [Candidate] = []
        var seen = Set<[String]>()
        for (i, c) in selected.enumerated() {
            let mine = comps[i]
            if hasProperAncestor(mine, in: all) { continue }
            if !seen.insert(mine).inserted { continue }
            result.append(c)
        }
        return result
    }

    /// Các candidate "bản trùng" được chọn mà bản giữ lại (keeper) cũng được chọn,
    /// hoặc nằm trong một candidate được chọn (hoặc chính là path đó). Tiến hành sẽ xoá hết mọi bản → phải chặn.
    public static func duplicateKeeperConflicts(selected: [Candidate]) -> [Candidate] {
        let all = Set(selected.map { components($0.url) })
        return selected.filter { c in
            guard case let .duplicateOf(keeper) = c.reasonKind else { return false }
            let k = components(keeper)
            return all.contains(k) || hasProperAncestor(k, in: all)
        }
    }

    private static func hasProperAncestor(_ path: [String], in set: Set<[String]>) -> Bool {
        guard path.count > 1 else { return false }
        for n in 1..<path.count where set.contains(Array(path.prefix(n))) { return true }
        return false
    }
}
