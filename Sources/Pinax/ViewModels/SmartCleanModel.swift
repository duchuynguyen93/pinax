import AppKit
import Foundation
import Observation
import PinaxCore

struct StorageInfo {
    var total: Int64 = 0
    var available: Int64 = 0
    /// nil = đang tính.
    var apps: Int64?
    var trash: Int64?
    /// true = không liệt kê được ~/.Trash (thiếu Full Disk Access).
    var trashUnreadable = false
}

@MainActor @Observable
final class SmartCleanModel {
    enum Phase { case idle, scanning, scanned }
    enum RuleProgress: Equatable { case running, done(count: Int, bytes: Int64) }
    enum CheckState { case off, on, mixed }

    /// Số item tối đa hiển thị trong một rule (đã sắp theo size giảm dần); checkbox của rule vẫn bao trùm tất cả.
    static let visibleItemLimit = 200

    let settings: AppSettings
    let history: HistoryModel
    let toast: ToastModel
    let rules: [any CleanRule] = RuleEngine.standard().rules

    private(set) var phase: Phase = .idle
    private(set) var results: [String: RuleResult] = [:]
    private(set) var progress: [String: RuleProgress] = [:]
    private(set) var selected: Set<UUID> = []
    private(set) var effective: [Candidate] = []
    private(set) var effectiveBytes: Int64 = 0
    private(set) var conflicts: [Candidate] = []
    private(set) var isPerforming = false
    private(set) var storage = StorageInfo()
    var expanded: Set<String> = []
    /// Dòng đang chọn (một dòng) để Space mở Quick Look; không liên quan tới checkbox.
    var focusedID: UUID?

    private var generation = 0
    private var scanTask: Task<Void, Never>?
    private var byID: [UUID: Candidate] = [:]

    init(settings: AppSettings, history: HistoryModel, toast: ToastModel) {
        self.settings = settings
        self.history = history
        self.toast = toast
        refreshStorage()
    }

    // MARK: Storage

    func refreshStorage() {
        let root = URL(fileURLWithPath: "/")
        let v = try? root.resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        storage.total = Int64(v?.volumeTotalCapacity ?? 0)
        storage.available = v?.volumeAvailableCapacityForImportantUsage ?? 0
        let appRoots = settings.applicationRoots
        let trash = settings.home.appendingPathComponent(".Trash", isDirectory: true)
        Task {
            let (apps, trashBytes, trashUnreadable) = await Task.detached(priority: .utility) {
                let apps = appRoots.reduce(Int64(0)) { $0 + ((try? SizeCalculator.allocatedSize(of: $1)) ?? 0) }
                var unreadable = false
                do {
                    _ = try FileManager.default.contentsOfDirectory(atPath: trash.path)
                } catch let e as NSError where e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoSuchFileError {
                    // Không có thư mục Thùng rác: coi như rỗng.
                } catch {
                    unreadable = true
                }
                let bytes = unreadable ? 0 : ((try? SizeCalculator.allocatedSize(of: trash)) ?? 0)
                return (apps, bytes, unreadable)
            }.value
            storage.apps = apps
            storage.trash = trashBytes
            storage.trashUnreadable = trashUnreadable
        }
    }

    // MARK: Scan

    func startScan() {
        guard phase != .scanning, !isPerforming else { return }
        generation += 1
        let gen = generation
        phase = .scanning
        results = [:]
        progress = [:]
        selected = []
        byID = [:]
        recompute()
        let ctx = settings.makeScanContext()
        let engine = RuleEngine(rules: rules)
        scanTask = Task { [self] in
            // onEvent chạy trên thread nền → đẩy về MainActor.
            let out = await engine.run(ctx) { event in
                Task { @MainActor [self] in self.handle(event, generation: gen) }
            }
            guard generation == gen, !Task.isCancelled else { return }
            finishScan(out)
        }
    }

    func cancelScan() {
        guard phase == .scanning else { return }
        generation += 1
        scanTask?.cancel()
        scanTask = nil
        phase = .idle
        progress = [:]
    }

    private func handle(_ event: RuleEvent, generation gen: Int) {
        guard gen == generation, phase == .scanning else { return }
        switch event {
        case .started(let id): progress[id] = .running
        case .finished(let id, let count, let bytes, _): progress[id] = .done(count: count, bytes: bytes)
        }
    }

    private func finishScan(_ out: [RuleResult]) {
        for r in out {
            let sorted = r.candidates.sorted { $0.size > $1.size }
            results[r.ruleID] = RuleResult(ruleID: r.ruleID, candidates: sorted, status: r.status)
            for c in sorted {
                byID[c.id] = c
                if c.preselected { selected.insert(c.id) }
            }
        }
        phase = .scanned
        recompute()
        refreshStorage()
    }

    // MARK: Selection

    func candidate(id: UUID) -> Candidate? { byID[id] }

    func candidates(for ruleID: String) -> [Candidate] { results[ruleID]?.candidates ?? [] }

    func checkState(for ruleID: String) -> CheckState {
        let items = candidates(for: ruleID)
        let n = items.reduce(0) { $0 + (selected.contains($1.id) ? 1 : 0) }
        return n == 0 ? .off : (n == items.count ? .on : .mixed)
    }

    func toggleRule(_ ruleID: String) {
        let ids = candidates(for: ruleID).map(\.id)
        if checkState(for: ruleID) == .on { selected.subtract(ids) } else { selected.formUnion(ids) }
        recompute()
    }

    func toggle(_ c: Candidate) {
        if selected.contains(c.id) { selected.remove(c.id) } else { selected.insert(c.id) }
        recompute()
    }

    func deselectConflicts() {
        selected.subtract(conflicts.map(\.id))
        recompute()
    }

    func toggleExpanded(_ ruleID: String) {
        if expanded.contains(ruleID) { expanded.remove(ruleID) } else { expanded.insert(ruleID) }
    }

    private func recompute() {
        let chosen = selected.compactMap { byID[$0] }
        effective = Selection.effectiveSelection(chosen).sorted { $0.size > $1.size }
        effectiveBytes = effective.reduce(0) { $0 + $1.size }
        conflicts = Selection.duplicateKeeperConflicts(selected: chosen).sorted { $0.url.path < $1.url.path }
    }

    var canMove: Bool { phase == .scanned && !effective.isEmpty && conflicts.isEmpty && !isPerforming }

    // MARK: Perform

    func moveSelectedToTrash() {
        guard canMove else { return }
        let items = effective
        let store = history.store
        let home = settings.home
        let title = L("Smart Clean: \(itemsText(items.count))", "Dọn dẹp thông minh: \(itemsText(items.count))")
        isPerforming = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Executor(store: store).perform(candidates: items, title: title, trasher: FileManagerTrasher(), home: home)
            }.value
            finishPerform(result)
        }
    }

    private func finishPerform(_ result: PerformResult) {
        isPerforming = false
        let done = result.outcomes.filter { $0.status == .done }.map(\.url)
        removeDone(done)
        history.reload()
        let problems = result.outcomes.compactMap(Problem.from)
        var message: String
        if done.isEmpty {
            message = L("Nothing was moved", "Chưa chuyển được mục nào")
        } else {
            message = L("Moved \(itemsText(done.count)) to the Trash", "Đã chuyển \(itemsText(done.count)) vào Thùng rác")
        }
        if !problems.isEmpty {
            message += L(" · \(problems.count) skipped or failed", " · \(problems.count) mục bị bỏ qua hoặc lỗi")
        }
        if let e = result.journalError {
            message += L(" · history could not be saved: \(e)", " · không ghi được lịch sử: \(e)")
        }
        toast.show(message, undoBatch: result.batch, problems: problems)
        refreshStorage()
    }

    /// Bỏ khỏi danh sách các mục đã chuyển (và mọi thứ nằm trong chúng).
    private func removeDone(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let donePaths = urls.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        func isGone(_ c: Candidate) -> Bool {
            let p = c.url.resolvingSymlinksInPath().standardizedFileURL.path
            return donePaths.contains { p == $0 || p.hasPrefix($0 + "/") }
        }
        for (id, r) in results {
            let kept = r.candidates.filter { !isGone($0) }
            for c in r.candidates where isGone(c) { byID[c.id] = nil; selected.remove(c.id) }
            results[id] = RuleResult(ruleID: id, candidates: kept, status: r.status)
        }
        recompute()
    }
}
