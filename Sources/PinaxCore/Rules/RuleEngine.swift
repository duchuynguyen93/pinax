import Foundation

public enum RuleEvent: Sendable {
    case started(ruleID: String)
    /// Kết quả thô của rule (trước dedupe giữa các rule).
    case finished(ruleID: String, count: Int, bytes: Int64, status: RuleStatus)
}

/// Chạy các rule song song, rồi dedupe giữa các rule theo thứ tự `rules` (một path chỉ ở rule đầu tiên).
public struct RuleEngine: Sendable {
    public let rules: [any CleanRule]

    public init(rules: [any CleanRule]) { self.rules = rules }

    /// 9 rule M1 theo đúng thứ tự bảng §3.4 ("leftovers" hoãn sang M1.5).
    public static func standard() -> RuleEngine {
        RuleEngine(rules: [
            DevCachesRule(), DevStaleRule(), DuplicatesRule(), InstallersRule(), MailDownloadsRule(),
            LargeFilesRule(), UnusedAppsRule(), ScreenRecordingsRule(), OldDownloadsRule(),
        ])
    }

    /// Trả kết quả theo thứ tự `rules`. Huỷ task → các rule đang chạy trả `.failed("cancelled")`.
    /// `onEvent` được gọi từ nhiều thread; caller tự đẩy về main nếu cần.
    public func run(_ ctx: ScanContext, onEvent: (@Sendable (RuleEvent) -> Void)? = nil) async -> [RuleResult] {
        let raw: [(Int, RuleResult)] = await withTaskGroup(of: (Int, RuleResult).self) { tg in
            for (index, rule) in rules.enumerated() {
                tg.addTask {
                    onEvent?(.started(ruleID: rule.id))
                    let result = await rule.scan(ctx)
                    onEvent?(.finished(ruleID: rule.id, count: result.candidates.count,
                                       bytes: result.candidates.reduce(0) { $0 + $1.size }, status: result.status))
                    return (index, result)
                }
            }
            var all: [(Int, RuleResult)] = []
            for await item in tg { all.append(item) }
            return all
        }
        return Self.dedupe(raw.sorted { $0.0 < $1.0 }.map(\.1))
    }

    /// Một path (và mọi thứ nằm trong một path đã được giữ) chỉ xuất hiện ở rule đầu tiên theo thứ tự.
    static func dedupe(_ results: [RuleResult]) -> [RuleResult] {
        var claimed = Set<String>()
        return results.map { result in
            var kept: [Candidate] = []
            for c in result.candidates {
                let path = RuleKit.resolvedPath(c.url).lowercased()
                if claimed.contains(path) || Self.hasClaimedAncestor(path, claimed) { continue }
                kept.append(c)
            }
            // Đánh dấu sau khi xử lý cả rule để hai candidate cùng rule không loại nhau.
            for c in kept { claimed.insert(RuleKit.resolvedPath(c.url).lowercased()) }
            return RuleResult(ruleID: result.ruleID, candidates: kept, status: result.status)
        }
    }

    private static func hasClaimedAncestor(_ path: String, _ claimed: Set<String>) -> Bool {
        var comps = path.split(separator: "/", omittingEmptySubsequences: true)
        while comps.count > 1 {
            comps.removeLast()
            if claimed.contains("/" + comps.joined(separator: "/")) { return true }
        }
        return false
    }
}
