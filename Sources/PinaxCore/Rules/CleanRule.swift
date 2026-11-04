import Foundation

/// Một quy tắc dọn dẹp. `id` ổn định (UI dùng để localize tiêu đề); `title` chỉ là fallback tiếng Anh.
public protocol CleanRule: Sendable {
    var id: String { get }
    var group: RuleGroup { get }
    var title: String { get }
    func scan(_ ctx: ScanContext) async -> RuleResult
}
