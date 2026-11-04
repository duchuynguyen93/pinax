import Foundation

/// `.app` trong applicationRoots có `lastUsed` KHÁC nil và cũ hơn `unusedAppDays`. Bỏ com.apple.* và Pinax.
public struct UnusedAppsRule: CleanRule {
    public let id = "unusedApps"
    public let group = RuleGroup.review
    public let title = "Unused apps"

    public init() {}

    public func scan(_ ctx: ScanContext) async -> RuleResult {
        RuleKit.run(id) {
            let guardian = ctx.pathGuard
            let cutoff = RuleKit.daysAgo(ctx.settings.unusedAppDays, from: ctx.now)
            var out: [Candidate] = []
            for app in ctx.installedApps.installedApps() {
                try Task.checkCancellation()
                if PathGuard.isProtectedApp(bundleID: app.bundleID) { continue }
                // nil = không biết → không bao giờ gắn cờ (§1.9)
                guard let last = ctx.lastUsed.info(for: app.url).lastUsed, last < cutoff else { continue }
                guard let meta = FileMeta.read(app.url), !meta.isSymlink else { continue }
                if let c = try RuleKit.makeCandidate(app.url, ctx: ctx, guardian: guardian,
                                                     reason: "Last opened \(last.formatted(date: .abbreviated, time: .omitted))",
                                                     kind: .lastUsed(last), lastUsed: last, preselected: false) {
                    out.append(c)
                }
            }
            return (out, .ok)
        }
    }
}
