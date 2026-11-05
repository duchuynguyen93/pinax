import AppKit
import Observation
import PinaxCore

/// Cờ huỷ đọc được từ thread nền.
final class TransferFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

/// Giá trị tiến độ mới nhất từ thread nền; main lấy ra theo nhịp 100 ms nên UI không bị ngập.
final class TransferProgressBox: @unchecked Sendable {
    private let lock = NSLock()
    private var latest: TransferProgress?
    private var dirty = false
    func set(_ p: TransferProgress) { lock.lock(); latest = p; dirty = true; lock.unlock() }
    func take() -> TransferProgress? {
        lock.lock(); defer { lock.unlock() }
        guard dirty else { return nil }
        dirty = false
        return latest
    }
}

@MainActor @Observable
final class TransferJob: Identifiable {
    let id = UUID()
    let title: String
    let kind: TransferKind
    fileprivate let plan: TransferPlan
    fileprivate let policy: ConflictPolicy
    fileprivate let onDone: (([URL]) -> Void)?
    /// nil tới khi runner báo lần đầu.
    private(set) var progress: TransferProgress?
    let totalItems: Int
    private(set) var isRunning = false
    @ObservationIgnored fileprivate let flag = TransferFlag()
    @ObservationIgnored fileprivate weak var queue: TransferQueue?

    fileprivate init(title: String, plan: TransferPlan, policy: ConflictPolicy, onDone: (([URL]) -> Void)?) {
        self.title = title
        self.kind = plan.kind
        self.plan = plan
        self.policy = policy
        self.onDone = onDone
        totalItems = plan.items.count
    }

    func cancel() { queue?.cancel(self) }

    fileprivate func setRunning() { isRunning = true }
    fileprivate func update(_ p: TransferProgress) { progress = p }
}

/// Hàng đợi chép / chuyển toàn app: chạy tuần tự từng job ngoài main thread, mỗi job một batch journal.
@MainActor @Observable
final class TransferQueue {
    private(set) var current: TransferJob?
    private(set) var queued: [TransferJob] = []

    @ObservationIgnored private let history: HistoryModel
    @ObservationIgnored private let toast: ToastModel
    @ObservationIgnored private let home: () -> URL
    /// QA: PINAX_QA_NOCLONE=1 ép chép thật (không clone APFS) để thấy tiến độ.
    @ObservationIgnored private let allowClone = ProcessInfo.processInfo.environment["PINAX_QA_NOCLONE"] != "1"

    init(history: HistoryModel, toast: ToastModel, home: @escaping () -> URL) {
        self.history = history
        self.toast = toast
        self.home = home
    }

    var isActive: Bool { current != nil }

    func enqueue(sources: [URL], destination: URL, kind: TransferKind, window: NSWindow?,
                 onDone: (([URL]) -> Void)? = nil) {
        guard !sources.isEmpty else { return }
        Task {
            let plan = await Task.detached(priority: .userInitiated) {
                TransferPlan.make(sources: sources, destination: destination, kind: kind)
            }.value
            guard !plan.items.isEmpty else { return }
            var policy = ConflictPolicy.keepBoth
            if kind != .duplicate, plan.conflictCount > 0 {
                guard let chosen = await askPolicy(plan, window: window) else { return }
                policy = chosen
            }
            let job = TransferJob(title: Self.title(kind, count: plan.items.count, destination: destination),
                                  plan: plan, policy: policy, onDone: onDone)
            job.queue = self
            queued.append(job)
            startNextIfIdle()
        }
    }

    func cancel(_ job: TransferJob) {
        if job === current { job.flag.set() } else { queued.removeAll { $0 === job } }
    }

    // MARK: Chạy

    private func startNextIfIdle() {
        guard current == nil, !queued.isEmpty else { return }
        let job = queued.removeFirst()
        current = job
        job.setRunning()

        let box = TransferProgressBox()
        let ticker = Task { @MainActor [weak job] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                if let p = box.take() { job?.update(p) }
            }
        }
        let store = history.store, home = home(), allowClone = allowClone
        let plan = job.plan, policy = job.policy, title = job.title, flag = job.flag
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                TransferRunner(executor: Executor(store: store), home: home, trasher: FileManagerTrasher(),
                               allowClone: allowClone)
                    .run(plan: plan, policy: policy, title: title,
                         progress: { box.set($0) }, isCancelled: { flag.isSet })
            }.value
            ticker.cancel()
            finish(job, result)
        }
    }

    private func finish(_ job: TransferJob, _ result: PerformResult) {
        current = nil
        history.reload()

        let done = result.outcomes.filter { $0.status == .done }.count
        let problems = result.outcomes.compactMap(Problem.from)
        var message: String
        if done > 0 {
            message = Self.doneText(job.kind, done)
        } else if !result.outcomes.isEmpty, result.outcomes.allSatisfy({ $0.status == .skipped(.protectedPath) }) {
            message = protectedLocationText()
        } else if !result.outcomes.isEmpty, result.outcomes.allSatisfy({ $0.status == .skipped(.insufficientSpace) }) {
            message = L("Not enough free space on the destination", "Ổ đích không đủ dung lượng trống")
        } else {
            message = Self.nothingText(job.kind)
        }
        if !problems.isEmpty && done > 0 {
            message += L(" · \(problems.count) skipped or failed", " · \(problems.count) mục bị bỏ qua hoặc lỗi")
        }
        if let e = result.journalError {
            message += L(" · history could not be saved: \(e)", " · không ghi được lịch sử: \(e)")
        }
        toast.show(message, undoBatch: result.batch, problems: problems)

        let created: [URL] = (result.batch?.ops ?? []).compactMap {
            switch $0 {
            case .copy(_, let created): created
            case .move(_, let to): to
            default: nil
            }
        }
        job.onDone?(created)
        startNextIfIdle()
    }

    // MARK: Hộp thoại trùng tên

    private func askPolicy(_ plan: TransferPlan, window: NSWindow?) async -> ConflictPolicy? {
        let n = plan.conflictCount
        let folder = FileManager.default.displayName(atPath: plan.destination.path)
        let alert = NSAlert()
        alert.alertStyle = .warning
        if n == 1, let item = plan.items.first(where: { $0.conflict && $0.skip == nil }) {
            let name = item.target.lastPathComponent
            alert.messageText = L("“\(name)” already exists in “\(folder)”", "“\(name)” đã có trong “\(folder)”")
        } else {
            alert.messageText = L("\(n) items already exist in “\(folder)”", "\(n) mục đã có trong “\(folder)”")
        }
        alert.informativeText = L("Replace moves the existing items to the Trash.",
                                  "Thay thế sẽ chuyển các mục cũ vào Thùng rác.")
        alert.addButton(withTitle: L("Keep Both", "Giữ cả hai"))
        alert.addButton(withTitle: L("Replace", "Thay thế"))
        alert.addButton(withTitle: L("Skip", "Bỏ qua"))
        alert.addButton(withTitle: L("Cancel", "Huỷ"))

        let response: NSApplication.ModalResponse
        if let window, window.isVisible {
            response = await withCheckedContinuation { cont in
                alert.beginSheetModal(for: window) { cont.resume(returning: $0) }
            }
        } else {
            response = alert.runModal()
        }
        switch response {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        case .alertThirdButtonReturn: return .skip
        default: return nil
        }
    }

    // MARK: Chữ

    private static func title(_ kind: TransferKind, count: Int, destination: URL) -> String {
        let items = itemsText(count)
        let dest = FileManager.default.displayName(atPath: destination.path)
        switch kind {
        case .copy: return L("Copy \(items) to \(dest)", "Chép \(items) vào \(dest)")
        case .move: return L("Move \(items) to \(dest)", "Chuyển \(items) vào \(dest)")
        case .duplicate: return L("Duplicate \(items) in \(dest)", "Nhân bản \(items) trong \(dest)")
        }
    }

    private static func doneText(_ kind: TransferKind, _ n: Int) -> String {
        switch kind {
        case .copy: L("Copied \(itemsText(n))", "Đã chép \(itemsText(n))")
        case .move: L("Moved \(itemsText(n))", "Đã chuyển \(itemsText(n))")
        case .duplicate: L("Duplicated \(itemsText(n))", "Đã nhân bản \(itemsText(n))")
        }
    }

    private static func nothingText(_ kind: TransferKind) -> String {
        switch kind {
        case .copy: L("Nothing was copied", "Chưa chép được mục nào")
        case .move: L("Nothing was moved", "Chưa chuyển được mục nào")
        case .duplicate: L("Nothing was duplicated", "Chưa nhân bản được mục nào")
        }
    }
}
