import Foundation

/// iOS DeviceSupport + `node_modules` của project có thư mục cha lâu không sửa.
public struct DevStaleRule: CleanRule {
    public let id = "devStale"
    public let group = RuleGroup.review
    public let title = "Stale developer data"

    public init() {}

    public func scan(_ ctx: ScanContext) async -> RuleResult {
        RuleKit.run(id) {
            let guardian = ctx.pathGuard
            var out: [Candidate] = []

            // iOS DeviceSupport/*
            let support = ctx.home.appendingPathComponent("Library/Developer/Xcode/iOS DeviceSupport", isDirectory: true)
            for url in (try? RuleKit.children(of: support)) ?? [] {
                try Task.checkCancellation()
                guard let meta = FileMeta.read(url), meta.isDirectory, !meta.isSymlink else { continue }
                if let c = try RuleKit.makeCandidate(url, ctx: ctx, guardian: guardian,
                                                     reason: "Xcode iOS device support: \(url.lastPathComponent)",
                                                     kind: .devCache("iOS DeviceSupport \(url.lastPathComponent)"),
                                                     lastUsed: nil, preselected: false) {
                    out.append(c)
                }
            }

            // node_modules của project cũ
            let cutoff = RuleKit.daysAgo(ctx.settings.staleProjectDays, from: ctx.now)
            let walker = DirectoryWalker(maxDepth: 6, includeDirectories: true)
            for root in ctx.settings.projectRoots {
                var found: [URL] = []
                try walker.walk(root) { entry in
                    guard entry.isDirectory else { return true }
                    if entry.url.lastPathComponent == "node_modules" {
                        found.append(entry.url)
                        return false // không đi vào chính node_modules
                    }
                    return true
                }
                for nm in found {
                    let parent = nm.deletingLastPathComponent()
                    guard let pm = FileMeta.read(parent), let modified = pm.modified, modified < cutoff else { continue }
                    if let c = try RuleKit.makeCandidate(nm, ctx: ctx, guardian: guardian,
                                                         reason: "node_modules of \(parent.lastPathComponent), untouched since \(modified.formatted(date: .abbreviated, time: .omitted))",
                                                         kind: .staleProject(parent.lastPathComponent),
                                                         lastUsed: nil, preselected: false) {
                        out.append(c)
                    }
                }
            }
            return (out, .ok)
        }
    }
}
