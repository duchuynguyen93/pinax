import Foundation

public enum TidySkipReason: Sendable, Equatable {
    case hidden, directory, symlinkOrAlias, inProgressDownload, recentlyModified, notAllowed
}

public struct TidyMove: Sendable, Equatable {
    public let from: URL
    public let to: URL
    public let kind: FileKind
    public let size: Int64
}

public struct TidyPlan: Sendable {
    public var tidyMoves: [TidyMove]
    /// Đã sắp theo thứ tự `FileKind.allCases`; chỉ gồm kind có move và thư mục chưa tồn tại.
    public var createDirs: [URL]
    public var skipped: [(URL, TidySkipReason)]
    public var bytesByKind: [FileKind: Int64]
    /// Thư mục đích của từng kind (dùng để lọc createDirs).
    var dirKinds: [URL: FileKind]

    /// Dạng `Executor.perform(moves:createDirs:title:home:)` nhận.
    public var moves: [(from: URL, to: URL)] { tidyMoves.map { (from: $0.from, to: $0.to) } }

    /// Chỉ giữ các nhóm được bật; createDirs của nhóm tắt cũng bị bỏ.
    public func filtered(kinds: Set<FileKind>) -> TidyPlan {
        var p = self
        p.tidyMoves = tidyMoves.filter { kinds.contains($0.kind) }
        p.createDirs = createDirs.filter { dirKinds[$0].map(kinds.contains) ?? false }
        p.bytesByKind = bytesByKind.filter { kinds.contains($0.key) }
        return p
    }
}

public enum TidyPlanner {
    private static let inProgressExts: Set<String> = ["crdownload", "download", "part", "partial", "opdownload"]
    static let recentWindow: TimeInterval = 60

    public static func plan(folder: URL, now: Date, home: URL) -> TidyPlan {
        let fm = FileManager.default
        let guardian = PathGuard(home: home)
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isAliasFileKey, .contentModificationDateKey]
        let entries = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [])) ?? [])
            .sorted { ($0.lastPathComponent.lowercased(), $0.lastPathComponent) < ($1.lastPathComponent.lowercased(), $1.lastPathComponent) }

        var plan = TidyPlan(tidyMoves: [], createDirs: [], skipped: [], bytesByKind: [:], dirKinds: [:])
        var taken: [FileKind: Set<String>] = [:] // tên (lowercased) đã có trên đĩa hoặc đã dành trong plan

        for url in entries {
            let name = url.lastPathComponent
            var u = url
            u.removeAllCachedResourceValues()
            let v = try? u.resourceValues(forKeys: Set(keys))
            let ext = url.pathExtension.lowercased()

            if name.hasPrefix(".") { plan.skipped.append((url, .hidden)); continue }
            if v?.isSymbolicLink == true || v?.isAliasFile == true { plan.skipped.append((url, .symlinkOrAlias)); continue }
            // Kiểm trước `directory` vì `.download` của Safari là package (thư mục).
            if inProgressExts.contains(ext) { plan.skipped.append((url, .inProgressDownload)); continue }
            if v?.isDirectory == true { plan.skipped.append((url, .directory)); continue }
            if let m = v?.contentModificationDate, abs(now.timeIntervalSince(m)) < recentWindow {
                plan.skipped.append((url, .recentlyModified)); continue
            }
            if !guardian.isAllowed(url) { plan.skipped.append((url, .notAllowed)); continue }

            let kind = FileKind.classify(url)
            let destDir = folder.appendingPathComponent(kind.folderName, isDirectory: true)
            if taken[kind] == nil {
                let existing = (try? fm.contentsOfDirectory(atPath: destDir.path)) ?? []
                taken[kind] = Set(existing.map { $0.lowercased() })
            }
            let finalName = uniqueName(name, taken: taken[kind] ?? [])
            let dest = destDir.appendingPathComponent(finalName)
            if !guardian.isAllowed(dest) { plan.skipped.append((url, .notAllowed)); continue }
            taken[kind]?.insert(finalName.lowercased())

            let size = (try? SizeCalculator.allocatedSize(of: url)) ?? 0
            plan.tidyMoves.append(TidyMove(from: url, to: dest, kind: kind, size: size))
            plan.bytesByKind[kind, default: 0] += size
        }

        for kind in FileKind.allCases where plan.tidyMoves.contains(where: { $0.kind == kind }) {
            let dir = folder.appendingPathComponent(kind.folderName, isDirectory: true)
            var st = stat()
            if lstat(dir.path, &st) != 0 {
                plan.createDirs.append(dir)
                plan.dirKinds[dir] = kind
            }
        }
        return plan
    }

    private static func uniqueName(_ name: String, taken: Set<String>) -> String {
        if !taken.contains(name.lowercased()) { return name }
        let ns = name as NSString
        let ext = ns.pathExtension
        let stem = ext.isEmpty ? name : ns.deletingPathExtension
        var n = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"
            if !taken.contains(candidate.lowercased()) { return candidate }
            n += 1
        }
    }
}
