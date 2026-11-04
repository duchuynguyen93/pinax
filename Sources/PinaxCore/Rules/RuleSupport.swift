import Foundation

extension ScanContext {
    /// PathGuard theo context: gốc /Applications là root ngoài home đầu tiên (test dùng thư mục tạm).
    var pathGuard: PathGuard {
        let homePath = home.resolvingSymlinksInPath().standardizedFileURL.path
        let appsRoot = applicationRoots.first { root in
            let p = root.resolvingSymlinksInPath().standardizedFileURL.path
            return p != homePath && !p.hasPrefix(homePath + "/")
        } ?? URL(fileURLWithPath: "/Applications")
        return PathGuard(home: home, applicationsRoot: appsRoot)
    }
}

/// Metadata đọc mới (xoá cache resource values), không theo symlink.
struct FileMeta {
    let url: URL
    let isRegular: Bool
    let isDirectory: Bool
    let isSymlink: Bool
    let isPackage: Bool
    /// Logical size (fileSize); thư mục = 0.
    let size: Int64
    let modified: Date?
    let created: Date?
    /// File iCloud chưa tải về (§1.5).
    let isICloudPlaceholder: Bool

    static func read(_ url: URL) -> FileMeta? {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .fileSizeKey,
            .contentModificationDateKey, .creationDateKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
        ]
        guard let v = try? fresh.resourceValues(forKeys: keys) else { return nil }
        let placeholder = v.isUbiquitousItem == true && v.ubiquitousItemDownloadingStatus != .current
        return FileMeta(url: url, isRegular: v.isRegularFile == true, isDirectory: v.isDirectory == true,
                        isSymlink: v.isSymbolicLink == true, isPackage: v.isPackage == true,
                        size: Int64(v.fileSize ?? 0), modified: v.contentModificationDate,
                        created: v.creationDate, isICloudPlaceholder: placeholder)
    }
}

enum RuleKit {
    static let megabyte: Int64 = 1024 * 1024

    /// Chạy thân rule; huỷ / lỗi không ném ra ngoài mà thành status.
    static func run(_ id: String, _ body: () throws -> (candidates: [Candidate], status: RuleStatus)) -> RuleResult {
        do {
            let r = try body()
            return RuleResult(ruleID: id, candidates: r.candidates, status: r.status)
        } catch is CancellationError {
            return RuleResult(ruleID: id, candidates: [], status: .failed("cancelled"))
        } catch {
            return RuleResult(ruleID: id, candidates: [], status: .failed(error.localizedDescription))
        }
    }

    /// Dựng candidate: qua PathGuard, fingerprint đọc mới, size allocated. nil nếu không hợp lệ.
    static func makeCandidate(_ url: URL, ctx: ScanContext, guardian: PathGuard, reason: String, kind: ReasonKind,
                              lastUsed: Date?, preselected: Bool) throws -> Candidate? {
        guard guardian.isAllowed(url), let fp = FileFingerprint.read(from: url) else { return nil }
        let size = try SizeCalculator.allocatedSize(of: url)
        return Candidate(url: url, size: size, fingerprint: fp, reason: reason, reasonKind: kind,
                         lastUsed: lastUsed, preselected: preselected)
    }

    /// Item cấp 1 của thư mục, bỏ file ẩn. Lỗi đọc → ném (để caller phân biệt permission).
    static func children(of dir: URL) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil,
                                                    options: [.skipsHiddenFiles])
    }

    static func resolvedPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func isInside(_ url: URL, _ dir: URL) -> Bool {
        let d = resolvedPath(dir).lowercased(), p = resolvedPath(url).lowercased()
        return p.hasPrefix(d.hasSuffix("/") ? d : d + "/")
    }

    static func isPermissionError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoPermissionError) { return true }
        if ns.domain == NSPOSIXErrorDomain && (ns.code == Int(EPERM) || ns.code == Int(EACCES)) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isPermissionError(underlying) }
        return false
    }

    static func isNoSuchFile(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && (ns.code == NSFileReadNoSuchFileError || ns.code == NSFileNoSuchFileError) { return true }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT) { return true }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error { return isNoSuchFile(underlying) }
        return false
    }

    /// (st_dev, st_ino) qua lstat; dùng nhận diện hardlink.
    static func inode(_ url: URL) -> (dev: Int64, ino: UInt64)? {
        var st = stat()
        guard lstat(url.path, &st) == 0 else { return nil }
        return (Int64(st.st_dev), UInt64(st.st_ino))
    }

    static func daysAgo(_ days: Int, from now: Date) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }
}
