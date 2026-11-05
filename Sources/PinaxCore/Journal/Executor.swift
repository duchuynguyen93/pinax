import Foundation

/// Thực thi + hoàn tác (§3.6). Mọi bước xoá đều đi qua `Trasher`, không có xoá vĩnh viễn file người dùng.
public struct Executor {
    public let store: JournalStore
    public let applicationsRoot: URL
    public let volumesRoot: URL
    public let isExternalVolume: PathGuard.VolumeCheck

    public init(store: JournalStore,
                applicationsRoot: URL = URL(fileURLWithPath: "/Applications"),
                volumesRoot: URL = URL(fileURLWithPath: "/Volumes"),
                isExternalVolume: @escaping PathGuard.VolumeCheck = PathGuard.defaultIsExternalVolume) {
        self.store = store
        self.applicationsRoot = applicationsRoot
        self.volumesRoot = volumesRoot
        self.isExternalVolume = isExternalVolume
    }

    func makeGuard(home: URL) -> PathGuard {
        PathGuard(home: home, applicationsRoot: applicationsRoot,
                  volumesRoot: volumesRoot, isExternalVolume: isExternalVolume)
    }

    // MARK: Perform: Trash

    public func perform(candidates: [Candidate], title: String, trasher: Trasher, home: URL) -> PerformResult {
        let guardian = makeGuard(home: home)
        var outcomes: [ItemOutcome] = []
        var ops: [JournalOp] = []

        for c in candidates {
            // Xác thực lại ngay trước khi thao tác (§1.2, §1.3).
            if !guardian.isAllowed(c.url) {
                outcomes.append(.init(url: c.url, status: .skipped(.protectedPath))); continue
            }
            if Self.isSymlink(c.url) {
                outcomes.append(.init(url: c.url, status: .skipped(.symlink))); continue
            }
            // App bundle của hệ thống / chính Pinax không bao giờ được chuyển đi, dù candidate đến từ đâu.
            if c.url.pathExtension.lowercased() == "app",
               PathGuard.isProtectedApp(bundleID: Bundle(url: c.url)?.infoDictionary?["CFBundleIdentifier"] as? String) {
                outcomes.append(.init(url: c.url, status: .skipped(.protectedPath))); continue
            }
            guard let now = FileFingerprint.read(from: c.url) else {
                outcomes.append(.init(url: c.url, status: .skipped(.missing))); continue
            }
            if !now.matches(c.fingerprint) {
                outcomes.append(.init(url: c.url, status: .skipped(.changedSinceScan))); continue
            }
            do {
                let trashed = try trasher.trash(c.url)
                ops.append(.trash(original: c.url, trashed: trashed))
                outcomes.append(.init(url: c.url, status: .done))
            } catch {
                outcomes.append(.init(url: c.url, status: .failed(error.localizedDescription)))
            }
        }
        return finish(title: title, ops: ops, outcomes: outcomes)
    }

    // MARK: Perform: Tidy (tạo thư mục + di chuyển)

    public func perform(moves: [(from: URL, to: URL)], createDirs: [URL], title: String, home: URL) -> PerformResult {
        let guardian = makeGuard(home: home)
        let fm = FileManager.default
        var outcomes: [ItemOutcome] = []
        var ops: [JournalOp] = []

        for dir in createDirs {
            guard guardian.isAllowed(dir) else {
                outcomes.append(.init(url: dir, status: .skipped(.protectedPath))); continue
            }
            // Đã có sẵn thì không phải do Pinax tạo → không ghi journal, không báo.
            if Self.exists(dir) { continue }
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: false)
                ops.append(.createDir(dir))
                outcomes.append(.init(url: dir, status: .done))
            } catch {
                outcomes.append(.init(url: dir, status: .failed(error.localizedDescription)))
            }
        }

        for m in moves {
            guard guardian.isAllowed(m.from), guardian.isAllowed(m.to) else {
                outcomes.append(.init(url: m.from, status: .skipped(.protectedPath))); continue
            }
            if Self.isSymlink(m.from) {
                outcomes.append(.init(url: m.from, status: .skipped(.symlink))); continue
            }
            guard Self.exists(m.from) else {
                outcomes.append(.init(url: m.from, status: .skipped(.missing))); continue
            }
            // Không bao giờ ghi đè đích. Ngoại lệ: đổi hoa/thường tên (cùng inode trên ổ không phân biệt hoa/thường).
            if Self.exists(m.to) && !Self.isCaseOnlyRename(m.from, m.to) {
                outcomes.append(.init(url: m.from, status: .skipped(.destinationExists))); continue
            }
            do {
                try fm.moveItem(at: m.from, to: m.to)
                ops.append(.move(from: m.from, to: m.to))
                outcomes.append(.init(url: m.from, status: .done))
            } catch {
                outcomes.append(.init(url: m.from, status: .failed(error.localizedDescription)))
            }
        }
        return finish(title: title, ops: ops, outcomes: outcomes)
    }

    /// Cho `TransferRunner` ghi một batch (journal trước khi trả về).
    public func record(title: String, ops: [JournalOp], outcomes: [ItemOutcome]) -> PerformResult {
        finish(title: title, ops: ops, outcomes: outcomes)
    }

    private func finish(title: String, ops: [JournalOp], outcomes: [ItemOutcome]) -> PerformResult {
        guard !ops.isEmpty else { return PerformResult(outcomes: outcomes, batch: nil, journalError: nil) }
        let batch = Batch(title: title, ops: ops)
        // Ghi journal TRƯỚC khi trả về cho UI (§1.7).
        do {
            try store.append(batch)
            return PerformResult(outcomes: outcomes, batch: batch, journalError: nil)
        } catch {
            return PerformResult(outcomes: outcomes, batch: batch, journalError: error.localizedDescription)
        }
    }

    // MARK: Undo

    /// Hoàn tác theo thứ tự ngược. Mỗi op có một outcome (url = vị trí được khôi phục / thư mục bị gỡ).
    @discardableResult
    public func undo(batch: Batch, trasher: Trasher = FileManagerTrasher()) -> [ItemOutcome] {
        let fm = FileManager.default
        var outcomes: [ItemOutcome] = []

        for op in batch.ops.reversed() {
            switch op {
            case let .trash(original, trashed):
                outcomes.append(restore(from: trashed, to: original))
            case let .move(from, to):
                outcomes.append(restore(from: to, to: from))
            case let .createDir(dir):
                outcomes.append(removeIfEmpty(dir, fm: fm))
            case let .copy(_, created):
                // Bản chép vào Thùng rác, không xoá vĩnh viễn.
                guard Self.exists(created) else { outcomes.append(.init(url: created, status: .skipped(.missing))); continue }
                do {
                    _ = try trasher.trash(created)
                    outcomes.append(.init(url: created, status: .done))
                } catch {
                    outcomes.append(.init(url: created, status: .failed(error.localizedDescription)))
                }
            }
        }
        do { try store.markUndone(batch.id) } catch {
            outcomes.append(.init(url: store.url, status: .failed("journal: \(error.localizedDescription)")))
        }
        return outcomes
    }

    private func restore(from source: URL, to original: URL) -> ItemOutcome {
        let fm = FileManager.default
        guard Self.exists(source) else { return .init(url: original, status: .skipped(.missing)) }
        if Self.exists(original) { return .init(url: original, status: .skipped(.originalOccupied)) }
        do {
            try fm.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: source, to: original)
            return .init(url: original, status: .done)
        } catch {
            return .init(url: original, status: .failed(error.localizedDescription))
        }
    }

    private func removeIfEmpty(_ dir: URL, fm: FileManager) -> ItemOutcome {
        guard Self.exists(dir), !Self.isSymlink(dir) else { return .init(url: dir, status: .skipped(.missing)) }
        guard let contents = try? fm.contentsOfDirectory(atPath: dir.path) else {
            return .init(url: dir, status: .failed("cannot read directory"))
        }
        guard contents.isEmpty else { return .init(url: dir, status: .skipped(.directoryNotEmpty)) }
        do {
            // NGOẠI LỆ DUY NHẤT dùng removeItem: thư mục RỖNG do chính Pinax tạo (Tidy). Không bao giờ dùng cho file người dùng.
            try fm.removeItem(at: dir)
            return .init(url: dir, status: .done)
        } catch {
            return .init(url: dir, status: .failed(error.localizedDescription))
        }
    }

    // MARK: lstat helpers (không theo symlink, nhận cả symlink hỏng)

    static func exists(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0
    }

    /// `a` → `A` trên ổ không phân biệt hoa/thường: đích "tồn tại" nhưng chính là nguồn.
    static func isCaseOnlyRename(_ from: URL, _ to: URL) -> Bool {
        guard from.path != to.path, from.path.lowercased() == to.path.lowercased() else { return false }
        var a = stat(), b = stat()
        guard lstat(from.path, &a) == 0, lstat(to.path, &b) == 0 else { return false }
        return a.st_dev == b.st_dev && a.st_ino == b.st_ino
    }

    static func isSymlink(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
    }
}
