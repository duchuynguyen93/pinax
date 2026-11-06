import Darwin
import Foundation

/// Quét dung lượng thật trên đĩa (st_blocks * 512) bằng fts(3). Chỉ đọc.
public struct SpaceScanner: Sendable {
    public struct Options: Sendable {
        public var minFileBytes: Int64 = 1_048_576
        /// Đường dẫn chuẩn hoá, gặp thì không đi vào.
        public var skipPaths: Set<String>

        public init(minFileBytes: Int64 = 1_048_576, skipPaths: Set<String> = []) {
            self.minFileBytes = minFileBytes
            self.skipPaths = skipPaths
        }

        /// Bỏ qua Containers / Group Containers: đọc vào là macOS hỏi quyền (TCC).
        public static func defaults(home: URL) -> Options {
            let lib = home.standardizedFileURL.appendingPathComponent("Library", isDirectory: true)
            return Options(skipPaths: [
                lib.appendingPathComponent("Containers").standardizedFileURL.path,
                lib.appendingPathComponent("Group Containers").standardizedFileURL.path,
            ])
        }
    }

    public struct Progress: Sendable {
        public var files: Int
        public var bytes: Int64
        public var currentPath: String
        /// Các con trực tiếp của gốc đã quét xong: (tên, size, isDirectory)
        public var finishedTopLevel: [(name: String, size: Int64, isDirectory: Bool)]
    }

    public struct Result: Sendable {
        public let root: SizeNode
        public let unreadableCount: Int
        public let duration: TimeInterval
    }

    public enum ScanError: Error, Sendable {
        case notADirectory(String)
        case cannotOpen(String, errno: Int32)
    }

    public let options: Options

    public init(options: Options) { self.options = options }

    private struct Frame {
        let node: SizeNode
        var smallCount = 0
        var smallBytes: Int64 = 0
    }

    /// Ném CancellationError khi task bị huỷ (kiểm mỗi ~512 entry). `progress` gọi tối đa ~10 lần/s, trên luồng quét.
    public func scan(root: URL, progress: @Sendable (Progress) -> Void = { _ in }) throws -> Result {
        let started = DispatchTime.now().uptimeNanoseconds
        let rootPath = root.standardizedFileURL.path

        var rst = stat()
        guard lstat(rootPath, &rst) == 0 else { throw ScanError.cannotOpen(rootPath, errno: errno) }
        guard (rst.st_mode & S_IFMT) == S_IFDIR else { throw ScanError.notADirectory(rootPath) }

        guard let cPath = strdup(rootPath) else { throw ScanError.cannotOpen(rootPath, errno: ENOMEM) }
        defer { free(cPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [cPath, nil]
        guard let fts = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
            throw ScanError.cannotOpen(rootPath, errno: errno)
        }
        defer { fts_close(fts) }

        let rootNode = SizeNode(name: rootPath, kind: .directory)
        var stack: [Frame] = []
        var pkgLevel: Int16?          // đang ở trong package ở level này
        var pkgNode: SizeNode?
        var seenLinks = Set<LinkKey>()
        var unreadable = 0
        var entries = 0
        var info = Progress(files: 0, bytes: 0, currentPath: rootPath, finishedTopLevel: [])
        var lastReport = started

        func report(force: Bool) {
            let now = DispatchTime.now().uptimeNanoseconds
            if force || now &- lastReport >= 100_000_000 {
                lastReport = now
                progress(info)
            }
        }

        while let ent = fts_read(fts) {
            if entries & 511 == 0, Task.isCancelled { throw CancellationError() }
            entries += 1

            let level = ent.pointee.fts_level
            let flag = Int32(ent.pointee.fts_info)
            // Chỉ dựng String tên khi cần (thư mục, file lớn): hàng triệu file nhỏ không cần.
            var name: String {
                withUnsafePointer(to: &ent.pointee.fts_name) { p in
                    p.withMemoryRebound(to: CChar.self, capacity: Int(ent.pointee.fts_namelen) + 1) {
                        String(cString: $0)
                    }
                }
            }
            let st = ent.pointee.fts_statp
            let blocks: Int64 = st.map { Int64($0.pointee.st_blocks) * 512 } ?? 0
            if entries & 63 == 0, let p = ent.pointee.fts_path {
                info.currentPath = String(cString: p)
            }

            switch flag {
            case Int32(FTS_D):
                if let pl = pkgLevel, level > pl {
                    pkgNode?.size += blocks
                    info.bytes += blocks
                    break
                }
                let path = ent.pointee.fts_path.map { String(cString: $0) } ?? rootPath
                if level == 0 {
                    rootNode.size = blocks
                    info.bytes += blocks
                    stack.append(Frame(node: rootNode))
                    break
                }
                let isSkipped = options.skipPaths.contains(path)
                var kind = SizeNode.Kind.directory
                if !isSkipped, Self.isPackage(path: path, name: name) { kind = .package }
                let node = SizeNode(name: name, kind: kind, size: isSkipped ? 0 : blocks)
                if isSkipped {
                    // FTS_SKIP vẫn trả lại chính entry này với FTS_DP → đẩy frame để FTS_DP pop đúng.
                    node.skipped = true
                    stack.append(Frame(node: node))
                    fts_set(fts, ent, Int32(FTS_SKIP))
                    break
                }
                info.bytes += blocks
                if kind == .package {
                    pkgLevel = level
                    pkgNode = node
                }
                stack.append(Frame(node: node))

            case Int32(FTS_DP):
                if let pl = pkgLevel, level > pl { break }
                if pkgLevel == level { pkgLevel = nil; pkgNode = nil }
                guard let frame = stack.popLast() else { break }
                finalize(frame)
                if level > 0 {
                    attach(frame.node, to: &stack, level: level, info: &info, finished: true)
                }

            case Int32(FTS_DNR), Int32(FTS_ERR), Int32(FTS_NS):
                let err = ent.pointee.fts_errno
                if let pl = pkgLevel, level > pl { break }
                // Thư mục đã FTS_D (đã có frame) nhưng mở không được: đóng frame, đánh dấu không đọc được.
                if stack.count == Int(level) + 1, stack[stack.count - 1].node.kind != .file {
                    let frame = stack.removeLast()
                    frame.node.isUnreadable = true
                    unreadable += 1
                    if pkgLevel == level { pkgLevel = nil; pkgNode = nil }
                    finalize(frame)
                    if level > 0 { attach(frame.node, to: &stack, level: level, info: &info, finished: true) }
                    break
                }
                if level == 0 { throw ScanError.cannotOpen(rootPath, errno: err) }
                // File biến mất giữa chừng: bỏ qua, không phải lỗi quyền.
                if err == ENOENT { break }
                // FTS_ERR/FTS_NS chưa qua FTS_D, không rõ file hay thư mục; coi như thư mục không đọc được.
                let node = SizeNode(name: name, kind: .directory, size: flag == Int32(FTS_DNR) ? blocks : 0)
                node.isUnreadable = true
                unreadable += 1
                attach(node, to: &stack, level: level, info: &info)

            case Int32(FTS_SL), Int32(FTS_SLNONE):
                break // symlink: tính 0, không thành node

            default: // FTS_F, FTS_DEFAULT (fifo, socket, device...)
                guard let st else { break }
                if (st.pointee.st_mode & S_IFMT) == S_IFREG, st.pointee.st_nlink > 1 {
                    let key = LinkKey(dev: Int64(st.pointee.st_dev), ino: UInt64(st.pointee.st_ino))
                    if !seenLinks.insert(key).inserted { break }
                }
                info.files += 1
                info.bytes += blocks
                if pkgLevel != nil, let pkg = pkgNode {
                    pkg.size += blocks
                    pkg.fileCount += 1
                } else if !stack.isEmpty {
                    if blocks >= options.minFileBytes {
                        let f = SizeNode(name: name, kind: .file, size: blocks, fileCount: 1)
                        f.parent = stack[stack.count - 1].node
                        let dir = stack[stack.count - 1].node
                        dir.children.append(f)
                        dir.size += blocks
                        dir.fileCount += 1
                    } else {
                        stack[stack.count - 1].smallCount += 1
                        stack[stack.count - 1].smallBytes += blocks
                    }
                }
            }
            report(force: false)
        }

        info.currentPath = rootPath
        report(force: true)
        let duration = Double(DispatchTime.now().uptimeNanoseconds &- started) / 1e9
        return Result(root: rootNode, unreadableCount: unreadable, duration: duration)
    }

    // MARK: - Helpers

    private struct LinkKey: Hashable { let dev: Int64; let ino: UInt64 }

    /// Package: có đuôi mở rộng và hệ thống xác nhận isPackage.
    private static func isPackage(path: String, name: String) -> Bool {
        guard (name as NSString).pathExtension.isEmpty == false else { return false }
        let v = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.isPackageKey])
        return v?.isPackage == true
    }

    /// Gom file nhỏ thành node others, sắp con.
    private func finalize(_ frame: Frame) {
        let node = frame.node
        if frame.smallCount > 0 {
            let o = SizeNode(name: "Smaller files", kind: .others, size: frame.smallBytes, fileCount: frame.smallCount)
            o.parent = node
            node.children.append(o)
            node.size += frame.smallBytes
            node.fileCount += frame.smallCount
        }
        node.children.sort(by: SizeNode.bySizeDesc)
    }

    /// Gắn node vào cha (đỉnh stack), cộng size/fileCount vào cha.
    private func attach(_ node: SizeNode, to stack: inout [Frame], level: Int16, info: inout Progress, finished: Bool = false) {
        guard let parent = stack.last?.node else { return }
        node.parent = parent
        parent.children.append(node)
        parent.size += node.size
        parent.fileCount += node.fileCount
        if finished, level == 1 {
            info.finishedTopLevel.append((node.name, node.size, node.kind == .directory || node.kind == .package))
        }
    }
}
