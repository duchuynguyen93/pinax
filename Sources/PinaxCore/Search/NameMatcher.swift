import Foundation

/// Khớp tên theo các từ của câu tìm: bỏ hoa/thường + dấu (đ → d), mỗi từ phải là chuỗi con.
public struct NameMatcher: Sendable {
    public let terms: [String]

    public init(_ query: String) {
        terms = Self.fold(query)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
    }

    public var isEmpty: Bool { terms.isEmpty }

    public func matches(_ name: String) -> Bool {
        if terms.isEmpty { return true }
        let folded = Self.fold(name)
        for t in terms where !folded.contains(t) { return false }
        return true
    }

    /// Fold dùng chung: bỏ hoa/thường + dấu, "đ"/"Đ" → "d" (folding không đổi đ).
    public static func fold(_ s: String) -> String {
        let f = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard f.contains(where: { $0 == "đ" || $0 == "Đ" }) else { return f }
        return f.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "d")
    }
}
