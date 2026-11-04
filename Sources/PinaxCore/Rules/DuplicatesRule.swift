import Foundation

/// File trùng nội dung trong Downloads, Desktop, Documents: size → hash 64 KB đầu → SHA-256 toàn file.
/// Chọn bản giữ: `lastUsed` mới nhất; hoà hoặc cùng nil thì `contentModificationDate` mới nhất, cuối cùng theo đường dẫn.
/// Group `.review`; từng candidate chỉ tick sẵn khi MỌI bản trong nhóm nằm trong Downloads.
public struct DuplicatesRule: CleanRule {
    public let id = "duplicates"
    public let group = RuleGroup.review
    public let title = "Duplicate files"
    public var minSize: Int64

    public init(minSize: Int64 = 1_048_576) { self.minSize = minSize }

    private struct Item {
        let url: URL
        let size: Int64
        let modified: Date
        var lastUsed: Date?
    }

    public func scan(_ ctx: ScanContext) async -> RuleResult {
        RuleKit.run(id) {
            let guardian = ctx.pathGuard
            let downloads = ctx.home.appendingPathComponent("Downloads", isDirectory: true)
            var bySize: [Int64: [Item]] = [:]
            var seenInodes = Set<String>() // hardlink / đường dẫn lặp: chỉ giữ một đại diện

            let walker = DirectoryWalker()
            for name in ["Downloads", "Desktop", "Documents"] {
                try walker.walk(ctx.home.appendingPathComponent(name, isDirectory: true)) { entry in
                    guard !entry.isDirectory, !entry.isPackage,
                          let meta = FileMeta.read(entry.url), meta.isRegular, !meta.isSymlink,
                          !meta.isICloudPlaceholder, meta.size >= minSize, let modified = meta.modified,
                          let ino = RuleKit.inode(entry.url),
                          seenInodes.insert("\(ino.dev):\(ino.ino)").inserted else { return true }
                    bySize[meta.size, default: []].append(Item(url: entry.url, size: meta.size, modified: modified))
                    return true
                }
            }

            var out: [Candidate] = []
            for (_, bucket) in bySize where bucket.count > 1 {
                for group in try Self.sameContentGroups(bucket) {
                    var members = group
                    for i in members.indices { members[i].lastUsed = ctx.lastUsed.info(for: members[i].url).lastUsed }
                    let keeper = members.max { Self.rank($0) < Self.rank($1) }!
                    let allInDownloads = members.allSatisfy { RuleKit.isInside($0.url, downloads) }
                    for m in members where m.url != keeper.url {
                        if let c = try RuleKit.makeCandidate(m.url, ctx: ctx, guardian: guardian,
                                                             reason: "Duplicate of \(keeper.url.lastPathComponent)",
                                                             kind: .duplicateOf(keeper.url), lastUsed: m.lastUsed,
                                                             preselected: allInDownloads) {
                            out.append(c)
                        }
                    }
                }
            }
            out.sort { $0.url.path < $1.url.path }
            return (out, .ok)
        }
    }

    /// Thứ tự giữ lại: lastUsed, rồi mtime, rồi đường dẫn (ổn định). Lớn hơn = ưu tiên giữ.
    private static func rank(_ i: Item) -> (Date, Date, String) {
        (i.lastUsed ?? .distantPast, i.modified, i.url.path)
    }

    private static func sameContentGroups(_ bucket: [Item]) throws -> [[Item]] {
        var partial: [Data: [Item]] = [:]
        for item in bucket {
            guard let h = try? FileHasher.sha256(of: item.url, limit: 64 * 1024) else { continue }
            try Task.checkCancellation()
            partial[h, default: []].append(item)
        }
        var groups: [[Item]] = []
        for (_, candidates) in partial where candidates.count > 1 {
            var full: [Data: [Item]] = [:]
            for item in candidates {
                try Task.checkCancellation()
                guard let h = try? FileHasher.sha256(of: item.url) else { continue }
                full[h, default: []].append(item)
            }
            groups.append(contentsOf: full.values.filter { $0.count > 1 })
        }
        return groups
    }
}
