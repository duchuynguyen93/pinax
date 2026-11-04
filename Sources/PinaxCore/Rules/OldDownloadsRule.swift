import Foundation

/// Item cấp 1 trong Downloads (file và thư mục) có max(lastUsed, dateAdded) cũ hơn N ngày; nil cả hai → bỏ.
public struct OldDownloadsRule: CleanRule {
    public let id = "oldDownloads"
    public let group = RuleGroup.review
    public let title = "Old downloads"

    public init() {}

    public func scan(_ ctx: ScanContext) async -> RuleResult {
        RuleKit.run(id) {
            let guardian = ctx.pathGuard
            let days = ctx.settings.oldDownloadDays
            let cutoff = RuleKit.daysAgo(days, from: ctx.now)
            let dir = ctx.home.appendingPathComponent("Downloads", isDirectory: true)
            var out: [Candidate] = []
            for url in (try? RuleKit.children(of: dir)) ?? [] {
                try Task.checkCancellation()
                guard let meta = FileMeta.read(url), !meta.isSymlink, !meta.isICloudPlaceholder else { continue }
                let info = ctx.lastUsed.info(for: url)
                guard let reference = [info.lastUsed, info.dateAdded].compactMap({ $0 }).max(),
                      reference < cutoff else { continue }
                if let c = try RuleKit.makeCandidate(url, ctx: ctx, guardian: guardian,
                                                     reason: "Not opened for over \(days) days",
                                                     kind: .olderThan(days: days), lastUsed: info.lastUsed,
                                                     preselected: false) {
                    out.append(c)
                }
            }
            return (out, .ok)
        }
    }
}
