import Foundation

/// Predicate Spotlight cho câu tìm: mỗi từ một điều kiện `kMDItemFSName LIKE[cd] "*từ*"`, nối AND.
public enum SpotlightPredicate {
    /// Trả nil khi câu tìm rỗng.
    public static func make(_ query: String) -> NSPredicate? {
        let raw = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !raw.isEmpty else { return nil }
        let subs = raw.map { term in
            NSPredicate(format: "kMDItemFSName LIKE[cd] %@", "*\(escape(term))*")
        }
        // NSMetadataQuery ném lỗi với AND chỉ một vế → một từ thì trả thẳng vế đó.
        return subs.count == 1 ? subs[0] : NSCompoundPredicate(andPredicateWithSubpredicates: subs)
    }

    /// Trong LIKE: `*` và `?` là wildcard, `\` là escape. Dấu nháy đã an toàn nhờ thay bằng %@.
    static func escape(_ term: String) -> String {
        var out = ""
        for ch in term {
            if ch == "\\" || ch == "*" || ch == "?" { out.append("\\") }
            out.append(ch)
        }
        return out
    }
}
