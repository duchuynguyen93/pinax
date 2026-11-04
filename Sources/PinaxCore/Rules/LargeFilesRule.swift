import Foundation

/// File ≥ `settings.largeFileMB` trong home, trừ `~/Library`, `~/.Trash` và nội dung package.
/// Spotlight trước; nil hoặc rỗng → fallback `DirectoryWalker`.
public struct LargeFilesRule: CleanRule {
    public let id = "largeFiles"
    public let group = RuleGroup.review
    public let title = "Large files"
    public let spotlight: SpotlightSearching

    public init(spotlight: SpotlightSearching = SpotlightQuery()) { self.spotlight = spotlight }

    public func scan(_ ctx: ScanContext) async -> RuleResult {
        RuleKit.run(id) {
            let guardian = ctx.pathGuard
            let threshold = Int64(ctx.settings.largeFileMB) * RuleKit.megabyte
            let excluded = [ctx.home.appendingPathComponent("Library", isDirectory: true),
                            ctx.home.appendingPathComponent(".Trash", isDirectory: true)]

            var urls: [URL] = []
            if let hits = spotlight.find(query: "kMDItemFSSize >= \(threshold)", in: ctx.home), !hits.isEmpty {
                urls = hits
            } else {
                // Spotlight bị tắt / hết giờ / không ra gì: tự duyệt.
                try DirectoryWalker(maxDepth: .max, includeDirectories: true).walk(ctx.home) { entry in
                    if entry.isDirectory {
                        return !excluded.contains { RuleKit.resolvedPath($0) == RuleKit.resolvedPath(entry.url) }
                    }
                    if !entry.isPackage { urls.append(entry.url) }
                    return true
                }
            }

            var seen = Set<String>()
            var out: [Candidate] = []
            for url in urls {
                try Task.checkCancellation()
                guard seen.insert(url.path).inserted,
                      !excluded.contains(where: { RuleKit.isInside(url, $0) }),
                      !Self.isInsidePackage(url, below: ctx.home),
                      let meta = FileMeta.read(url), meta.isRegular, !meta.isSymlink,
                      !meta.isICloudPlaceholder, meta.size >= threshold else { continue }
                if let c = try RuleKit.makeCandidate(url, ctx: ctx, guardian: guardian,
                                                     reason: "Large file",
                                                     kind: .large, lastUsed: ctx.lastUsed.info(for: url).lastUsed,
                                                     preselected: false) {
                    out.append(c)
                }
            }
            out.sort { $0.size > $1.size }
            return (out, .ok)
        }
    }

    /// Có tổ tiên (dưới home) là package, vd `Photos Library.photoslibrary`, `.app`.
    static func isInsidePackage(_ url: URL, below home: URL) -> Bool {
        let homePath = RuleKit.resolvedPath(home)
        var dir = url.deletingLastPathComponent()
        while RuleKit.resolvedPath(dir).count > homePath.count, RuleKit.resolvedPath(dir).hasPrefix(homePath) {
            if (try? dir.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true { return true }
            dir = dir.deletingLastPathComponent()
        }
        return false
    }
}
