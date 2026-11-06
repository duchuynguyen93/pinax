import Darwin
import Foundation

/// Duyệt fts tìm theo tên (dùng khi Spotlight không áp được). Chỉ đọc.
public struct NameSearch: Sendable {
    public struct Options: Sendable {
        /// false: bỏ qua mục bắt đầu bằng "." và không đi vào thư mục ẩn.
        public var includeHidden: Bool = false
        public var limit: Int = 5000
        /// Đường dẫn chuẩn hoá, gặp thì không đi vào (Containers…).
        public var skipPaths: Set<String> = []

        public init(includeHidden: Bool = false, limit: Int = 5000, skipPaths: Set<String> = []) {
            self.includeHidden = includeHidden
            self.limit = limit
            self.skipPaths = skipPaths
        }
    }

    public enum SearchError: Error, Sendable {
        case notADirectory(String)
        case cannotOpen(String, errno: Int32)
    }

    public let options: Options

    public init(options: Options) { self.options = options }

    /// Gọi `found` theo lô (≤ ~10 lần/s, kèm lô cuối). Không theo symlink (FTS_PHYSICAL), không vượt ổ (FTS_XDEV),
    /// không đi vào package (package vẫn có thể là kết quả). Gốc không tính là kết quả. Dừng ở `limit`.
    /// Ném CancellationError khi task bị huỷ. Trả về true nếu bị cắt ở limit.
    public func run(root: URL, matcher: NameMatcher, found: @Sendable ([URL]) -> Void) throws -> Bool {
        let rootPath = root.standardizedFileURL.path
        var rst = stat()
        guard lstat(rootPath, &rst) == 0 else { throw SearchError.cannotOpen(rootPath, errno: errno) }
        guard (rst.st_mode & S_IFMT) == S_IFDIR else { throw SearchError.notADirectory(rootPath) }

        guard let cPath = strdup(rootPath) else { throw SearchError.cannotOpen(rootPath, errno: ENOMEM) }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            throw SearchError.cannotOpen(rootPath, errno: errno)
        }
        defer { fts_close(fts) }

        var batch: [URL] = []
        var count = 0
        var entries = 0
        var lastFlush = DispatchTime.now().uptimeNanoseconds
        func flush(force: Bool) {
            guard !batch.isEmpty else { return }
            let now = DispatchTime.now().uptimeNanoseconds
            if force || now &- lastFlush >= 100_000_000 {
                lastFlush = now
                found(batch)
                batch.removeAll(keepingCapacity: true)
            }
        }

        var truncated = false
        while let ent = fts_read(fts) {
            if entries & 255 == 0, Task.isCancelled { throw CancellationError() }
            entries += 1

            let flag = Int32(ent.pointee.fts_info)
            // FTS_SKIP trả lại chính thư mục với FTS_DP, và gốc không phải kết quả.
            if flag == Int32(FTS_DP) || ent.pointee.fts_level == 0 { continue }
            if flag == Int32(FTS_DNR) || flag == Int32(FTS_ERR) || flag == Int32(FTS_NS) { continue }

            let name = withUnsafePointer(to: &ent.pointee.fts_name) { p in
                p.withMemoryRebound(to: CChar.self, capacity: Int(ent.pointee.fts_namelen) + 1) {
                    String(cString: $0)
                }
            }
            let isDir = flag == Int32(FTS_D)
            if !options.includeHidden, name.hasPrefix(".") {
                if isDir { fts_set(fts, ent, Int32(FTS_SKIP)) }
                continue
            }
            guard let cp = ent.pointee.fts_path else { continue }
            let path = String(cString: cp)
            if isDir, options.skipPaths.contains(path) {
                fts_set(fts, ent, Int32(FTS_SKIP))
                continue
            }
            if isDir, !(name as NSString).pathExtension.isEmpty {
                let isPkg = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isPackageKey]).isPackage) == true
                if isPkg { fts_set(fts, ent, Int32(FTS_SKIP)) }
            }

            guard matcher.matches(name) else { continue }
            batch.append(URL(fileURLWithPath: path, isDirectory: isDir))
            count += 1
            if count >= options.limit {
                truncated = true
                break
            }
            flush(force: false)
        }
        flush(force: true)
        return truncated
    }
}
