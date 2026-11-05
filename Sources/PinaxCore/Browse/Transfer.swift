import Foundation

public enum TransferKind: Sendable { case copy, move, duplicate }
public enum ConflictPolicy: Sendable { case replace, keepBoth, skip }
public enum NameStyle: Sendable {
    /// `tên 2.ext`, `tên 3.ext`.
    case numbered
    /// `tên copy.ext`, `tên copy 2.ext`.
    case copySuffix
}

public enum TransferError: Error, LocalizedError, Equatable {
    case cancelled
    case posix(Int32)
    public var errorDescription: String? {
        switch self {
        case .cancelled: "Cancelled"
        case let .posix(code): String(cString: strerror(code))
        }
    }
}

// MARK: Đặt tên

public enum TransferNaming {
    /// Tên chưa bị chiếm trong `dir` (so không phân biệt hoa/thường như APFS; symlink hỏng cũng tính là đã chiếm).
    /// Thư mục không có đuôi thì không tách đuôi; package (`X.app`) giữ đuôi. Chỉ tách đuôi cuối (`a.tar.gz` → `a.tar 2.gz`).
    public static func availableName(for name: String, in dir: URL, isDirectory: Bool, style: NameStyle) -> String {
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).map { $0.lowercased() })
        return availableName(for: name, existing: existing, isDirectory: isDirectory, style: style)
    }

    static func availableName(for name: String, existing: Set<String>, isDirectory: Bool, style: NameStyle) -> String {
        let ext = (name as NSString).pathExtension
        let hasExt = !ext.isEmpty
        let base = hasExt ? String(name.dropLast(ext.count + 1)) : name
        let suffix = hasExt ? ".\(ext)" : ""
        func candidate(_ n: Int) -> String {
            switch style {
            case .numbered: "\(base) \(n)\(suffix)"
            case .copySuffix: n == 1 ? "\(base) copy\(suffix)" : "\(base) copy \(n)\(suffix)"
            }
        }
        var n = style == .numbered ? 2 : 1
        while existing.contains(candidate(n).lowercased()) { n += 1 }
        return candidate(n)
    }
}

// MARK: Plan

public struct TransferItem: Equatable, Sendable {
    public let source: URL
    public let target: URL
    /// Đích đã tồn tại (và không phải chính nguồn đổi hoa/thường).
    public let conflict: Bool
    /// Nguồn và thư mục đích khác ổ (chỉ có nghĩa với move).
    public let crossVolume: Bool
    /// Không làm item này, kèm lý do.
    public let skip: SkipReason?
}

public struct TransferPlan: Sendable {
    public let kind: TransferKind
    public let destination: URL
    /// Move vào chính thư mục cha của nguồn là no-op: item bị bỏ khỏi `items` (không có outcome).
    public let items: [TransferItem]

    public var conflictCount: Int { items.filter { $0.conflict && $0.skip == nil }.count }

    public static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let ka = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        let kb = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier
        guard let ka, let kb else { return true }
        return ka.isEqual(kb)
    }

    public static func make(sources: [URL], destination: URL, kind: TransferKind,
                            isSameVolume: (URL, URL) -> Bool = TransferPlan.sameVolume) -> TransferPlan {
        let destPath = destination.standardizedFileURL.path
        var items: [TransferItem] = []
        // Tên đã dành trong lượt này (để hai nguồn cùng tên không đặt trùng nhau).
        var reserved = Set<String>()
        let existing = Set(((try? FileManager.default.contentsOfDirectory(atPath: destination.path)) ?? []).map { $0.lowercased() })

        for src in sources {
            let name = src.lastPathComponent
            let sameParent = src.deletingLastPathComponent().standardizedFileURL.path == destPath
            let crossVolume = kind == .move && !isSameVolume(src, destination)
            func item(_ target: URL, conflict: Bool = false, skip: SkipReason? = nil) -> TransferItem {
                TransferItem(source: src, target: target, conflict: conflict, crossVolume: crossVolume, skip: skip)
            }

            guard let st = lstatInfo(src) else {
                items.append(item(destination.appendingPathComponent(name), skip: .missing)); continue
            }
            if kind == .move && sameParent { continue }

            if st.isDirectory {
                let s = src.standardizedFileURL.path + "/"
                if (destPath + "/").hasPrefix(s) {
                    items.append(item(destination.appendingPathComponent(name), skip: .intoItself)); continue
                }
            }

            if kind == .duplicate || (kind == .copy && sameParent) {
                let new = TransferNaming.availableName(for: name, existing: existing.union(reserved),
                                                       isDirectory: st.isDirectory, style: .copySuffix)
                reserved.insert(new.lowercased())
                items.append(item(destination.appendingPathComponent(new, isDirectory: st.isDirectory)))
                continue
            }

            let target = destination.appendingPathComponent(name, isDirectory: st.isDirectory)
            let taken = Executor.exists(target) && !Executor.isCaseOnlyRename(src, target)
            items.append(item(target, conflict: taken))
        }
        return TransferPlan(kind: kind, destination: destination, items: items)
    }
}

struct LstatInfo { let isDirectory: Bool; let size: Int64 }

func lstatInfo(_ url: URL) -> LstatInfo? {
    var st = stat()
    guard lstat(url.path, &st) == 0 else { return nil }
    return LstatInfo(isDirectory: (st.st_mode & S_IFMT) == S_IFDIR, size: Int64(st.st_size))
}

/// Tổng kích thước (lstat, không theo symlink).
func transferSize(of url: URL) -> Int64 {
    guard let info = lstatInfo(url) else { return 0 }
    guard info.isDirectory else { return info.size }
    var total: Int64 = 0
    if let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: []) {
        for case let u as URL in e { total += lstatInfo(u).map { $0.isDirectory ? 0 : $0.size } ?? 0 }
    }
    return total
}

// MARK: Tiến độ

public struct TransferProgress: Sendable {
    public var completedBytes: Int64
    public var totalBytes: Int64
    public var completedItems: Int
    public var totalItems: Int
    public var currentName: String
}

// MARK: copyfile(3)

enum CopyFile {
    private final class Box {
        let progress: (Int64) -> Void
        let isCancelled: () -> Bool
        var lastCopied: Int64 = 0
        var cancelled = false
        init(progress: @escaping (Int64) -> Void, isCancelled: @escaping () -> Bool) {
            self.progress = progress
            self.isCancelled = isCancelled
        }
    }

    /// `progress` nhận số byte vừa chép thêm (delta). Huỷ → `TransferError.cancelled`.
    static func copy(from: URL, to: URL, allowClone: Bool = true,
                     progress: (Int64) -> Void, isCancelled: () -> Bool) throws {
        try withoutActuallyEscaping(progress) { progress in
            try withoutActuallyEscaping(isCancelled) { isCancelled in
                let box = Box(progress: progress, isCancelled: isCancelled)
                let state = copyfile_state_alloc()
                defer { copyfile_state_free(state) }

                let callback: copyfile_callback_t = { what, stage, state, _, _, ctx in
                    guard let ctx else { return Int32(COPYFILE_CONTINUE) }
                    let box = Unmanaged<Box>.fromOpaque(ctx).takeUnretainedValue()
                    if box.isCancelled() { box.cancelled = true; return Int32(COPYFILE_QUIT) }
                    if what == COPYFILE_COPY_DATA {
                        if stage == COPYFILE_START {
                            box.lastCopied = 0
                        } else if stage == COPYFILE_PROGRESS || stage == COPYFILE_FINISH {
                            var copied: off_t = 0
                            copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                            let c = Int64(copied)
                            if c > box.lastCopied { box.progress(c - box.lastCopied); box.lastCopied = c }
                        }
                    }
                    if stage == COPYFILE_ERR { return Int32(COPYFILE_QUIT) }
                    return Int32(COPYFILE_CONTINUE)
                }
                let ctx = Unmanaged.passUnretained(box).toOpaque()
                copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
                copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), ctx)

                var flags = UInt32(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_NOFOLLOW)
                if allowClone { flags |= UInt32(COPYFILE_CLONE) }
                let rc = withExtendedLifetime(box) { copyfile(from.path, to.path, state, flags) }
                if rc != 0 {
                    if box.cancelled { throw TransferError.cancelled }
                    throw TransferError.posix(errno)
                }
            }
        }
    }
}

// MARK: Runner

public struct TransferRunner {
    public let executor: Executor
    public let home: URL
    public let trasher: Trasher
    public let allowClone: Bool
    public let availableSpace: (URL) -> Int64?

    public init(executor: Executor, home: URL, trasher: Trasher, allowClone: Bool = true,
                availableSpace: @escaping (URL) -> Int64? = TransferRunner.defaultAvailableSpace) {
        self.executor = executor
        self.home = home
        self.trasher = trasher
        self.allowClone = allowClone
        self.availableSpace = availableSpace
    }

    public static func defaultAvailableSpace(_ dir: URL) -> Int64? {
        (try? dir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage
    }

    private func needsCopy(_ plan: TransferPlan, _ item: TransferItem) -> Bool {
        plan.kind != .move || item.crossVolume
    }

    public func run(plan: TransferPlan, policy: ConflictPolicy, title: String,
                    progress: (TransferProgress) -> Void = { _ in },
                    isCancelled: () -> Bool = { false }) -> PerformResult {
        let items = plan.items
        let active = items.filter { $0.skip == nil }

        // Dung lượng: chỉ khi thật sự chép sang ổ khác.
        let copying = active.filter { needsCopy(plan, $0) }
        let sizes: [URL: Int64] = Dictionary(copying.map { ($0.source, transferSize(of: $0.source)) },
                                             uniquingKeysWith: { a, _ in a })
        let crossCopy = copying.filter { plan.kind == .move || !TransferPlan.sameVolume($0.source, plan.destination) }
        if !crossCopy.isEmpty, let free = availableSpace(plan.destination),
           crossCopy.reduce(Int64(0), { $0 + (sizes[$1.source] ?? 0) }) > free {
            return PerformResult(outcomes: items.map { .init(url: $0.source, status: .skipped(.insufficientSpace)) },
                                 batch: nil, journalError: nil)
        }

        let guardian = executor.makeGuard(home: home)
        let fm = FileManager.default
        var prog = TransferProgress(completedBytes: 0, totalBytes: sizes.values.reduce(0, +),
                                    completedItems: 0, totalItems: items.count, currentName: "")
        var ops: [JournalOp] = []
        var outcomes: [ItemOutcome] = []
        var cancelled = false

        for item in items {
            let src = item.source
            prog.currentName = src.lastPathComponent
            defer { prog.completedItems += 1; progress(prog) }

            if cancelled || isCancelled() {
                cancelled = true
                outcomes.append(.init(url: src, status: .skipped(.cancelled))); continue
            }
            if let reason = item.skip { outcomes.append(.init(url: src, status: .skipped(reason))); continue }

            let isMove = plan.kind == .move
            if !guardian.isAllowed(item.target) || (isMove && !guardian.isAllowed(src))
                || (isMove && src.pathExtension.lowercased() == "app"
                    && PathGuard.isProtectedApp(bundleID: Bundle(url: src)?.infoDictionary?["CFBundleIdentifier"] as? String)) {
                outcomes.append(.init(url: src, status: .skipped(.protectedPath))); continue
            }
            guard Executor.exists(src) else { outcomes.append(.init(url: src, status: .skipped(.missing))); continue }

            // Trùng tên lúc chạy (kiểm lại bằng lstat).
            var target = item.target
            var replacing = false
            if Executor.exists(target) && !Executor.isCaseOnlyRename(src, target) {
                if plan.kind == .duplicate {
                    target = target.deletingLastPathComponent().appendingPathComponent(
                        TransferNaming.availableName(for: src.lastPathComponent, in: plan.destination,
                                                     isDirectory: lstatInfo(src)?.isDirectory ?? false, style: .copySuffix))
                } else {
                    switch policy {
                    case .skip:
                        outcomes.append(.init(url: src, status: .skipped(.destinationExists))); continue
                    case .keepBoth:
                        target = target.deletingLastPathComponent().appendingPathComponent(
                            TransferNaming.availableName(for: target.lastPathComponent, in: target.deletingLastPathComponent(),
                                                         isDirectory: lstatInfo(src)?.isDirectory ?? false, style: .numbered))
                    case .replace:
                        // Mục cũ chứa chính nguồn (chuyển `x/foo/foo` ra `x`): thay thế sẽ kéo nguồn theo vào Thùng rác.
                        if (src.standardizedFileURL.path + "/").hasPrefix(target.standardizedFileURL.path + "/") {
                            outcomes.append(.init(url: src, status: .skipped(.intoItself))); continue
                        }
                        replacing = true
                    }
                }
            }

            // Trả về nil nếu thành công, ngược lại outcome kết thúc item.
            func trashExisting() -> ItemOutcome? {
                do {
                    let trashed = try trasher.trash(target)
                    ops.append(.trash(original: target, trashed: trashed))
                    return nil
                } catch {
                    return .init(url: src, status: .failed(error.localizedDescription))
                }
            }

            if needsCopy(plan, item) {
                let base = prog.completedBytes
                let size = sizes[src] ?? 0
                let dir = target.deletingLastPathComponent()
                let tmp = dir.appendingPathComponent(Self.partialName(for: target.lastPathComponent))
                do {
                    try CopyFile.copy(from: src, to: tmp, allowClone: allowClone, progress: { delta in
                        prog.completedBytes = min(prog.completedBytes + delta, base + size)
                        progress(prog)
                    }, isCancelled: isCancelled)
                } catch {
                    _ = try? Executor.exists(tmp) ? trasher.trash(tmp) : nil
                    if let e = error as? TransferError, e == .cancelled {
                        cancelled = true
                        outcomes.append(.init(url: src, status: .skipped(.cancelled)))
                    } else {
                        outcomes.append(.init(url: src, status: .failed(error.localizedDescription)))
                    }
                    prog.completedBytes = base
                    continue
                }
                prog.completedBytes = base + size
                if replacing, let fail = trashExisting() {
                    _ = try? trasher.trash(tmp)
                    outcomes.append(fail); continue
                }
                if renamex_np(tmp.path, target.path, UInt32(RENAME_EXCL)) != 0 {
                    let code = errno
                    _ = try? trasher.trash(tmp)
                    outcomes.append(.init(url: src, status: code == EEXIST ? .skipped(.destinationExists)
                                                                          : .failed(TransferError.posix(code).localizedDescription)))
                    continue
                }
                ops.append(.copy(source: src, created: target))
                if isMove {
                    // Khác ổ: nguồn vào Thùng rác, không xoá vĩnh viễn.
                    do {
                        let trashed = try trasher.trash(src)
                        ops.append(.trash(original: src, trashed: trashed))
                    } catch {
                        outcomes.append(.init(url: src, status: .failed(
                            "Copied, but the original couldn't be moved to the Trash: \(error.localizedDescription)")))
                        continue
                    }
                }
                outcomes.append(.init(url: src, status: .done))
            } else {
                // Move cùng ổ.
                if replacing, let fail = trashExisting() { outcomes.append(fail); continue }
                if Executor.exists(target) && !Executor.isCaseOnlyRename(src, target) {
                    outcomes.append(.init(url: src, status: .skipped(.destinationExists))); continue
                }
                do {
                    try fm.moveItem(at: src, to: target)
                    ops.append(.move(from: src, to: target))
                    outcomes.append(.init(url: src, status: .done))
                } catch {
                    outcomes.append(.init(url: src, status: .failed(error.localizedDescription)))
                }
            }
        }
        return executor.record(title: title, ops: ops, outcomes: outcomes)
    }

    /// `.pinax-partial-<8 hex>-<tên>`, tên bị cắt để cả thành phần ≤ 255 byte UTF-8.
    static func partialName(for name: String) -> String {
        let prefix = ".pinax-partial-" + String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(8).lowercased()) + "-"
        var room = 255 - prefix.utf8.count
        var out = ""
        for ch in name {
            let n = String(ch).utf8.count
            if n > room { break }
            out.append(ch); room -= n
        }
        return prefix + out
    }
}
