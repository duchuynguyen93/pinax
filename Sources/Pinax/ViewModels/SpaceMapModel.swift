import Foundation
import Observation
import PinaxCore

enum SpaceMapState {
    case idle
    /// nil = vừa bắt đầu, chưa có báo cáo tiến độ nào.
    case scanning(SpaceScanner.Progress?)
    case done
    case failed(String)
}

/// Quét một thư mục, xem cái gì nặng nhất, đi sâu, rồi đưa vào Thùng rác (qua Executor).
@MainActor @Observable
final class SpaceMapModel {
    let settings: AppSettings
    let history: HistoryModel
    let toast: ToastModel
    /// Gọi sau khi chuyển vào Thùng rác để Smart Clean cập nhật dung lượng.
    var onChanged: (() -> Void)?

    private(set) var state: SpaceMapState = .idle
    private(set) var result: SpaceScanner.Result?
    private(set) var current: SizeNode?
    /// Tăng sau mỗi lần sửa cây (SizeNode không observable) để SwiftUI vẽ lại.
    private(set) var treeVersion = 0
    private(set) var unreadableCount = 0
    /// Cây đã cũ (có thay đổi từ ngoài, ví dụ hoàn tác).
    private(set) var isStale = false
    private(set) var isBusy = false
    private(set) var scanningSkipped: Set<ObjectIdentifier> = []
    private(set) var scanRoot: URL?
    var selection: Set<ObjectIdentifier> = []
    var confirmCandidates: [Candidate]?

    private var task: Task<Void, Never>?
    private var generation = 0
    private var pendingTrash: [SizeNode] = []

    init(settings: AppSettings, history: HistoryModel, toast: ToastModel) {
        self.settings = settings
        self.history = history
        self.toast = toast
    }

    // MARK: Quét

    var isScanning: Bool {
        if case .scanning = state { return true }
        return false
    }

    func scanHome() { scan(settings.home) }

    func scan(_ url: URL) {
        task?.cancel()
        generation += 1
        let gen = generation
        scanRoot = url
        isStale = false
        selection = []
        state = .scanning(nil)
        let options = SpaceScanner.Options.defaults(home: settings.home)
        task = Task.detached(priority: .userInitiated) { [weak self] in
            let owner = self
            do {
                let r = try SpaceScanner(options: options).scan(root: url) { p in
                    Task { @MainActor in owner?.report(p, gen: gen) }
                }
                try Task.checkCancellation()
                await MainActor.run { owner?.finish(r, gen: gen) }
            } catch is CancellationError {
                // Đã huỷ: cancel() / lượt quét mới lo trạng thái.
            } catch {
                let message = error.localizedDescription
                await MainActor.run { owner?.fail(message, gen: gen) }
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        state = result == nil ? .idle : .done
    }

    func rescan() {
        if let url = scanRoot { scan(url) }
    }

    private func report(_ p: SpaceScanner.Progress, gen: Int) {
        guard gen == generation, isScanning else { return }
        state = .scanning(p)
    }

    private func finish(_ r: SpaceScanner.Result, gen: Int) {
        guard gen == generation else { return }
        task = nil
        result = r
        current = r.root
        unreadableCount = r.unreadableCount
        treeVersion += 1
        state = .done
    }

    private func fail(_ message: String, gen: Int) {
        guard gen == generation else { return }
        task = nil
        state = .failed(message)
    }

    /// Quét riêng một node `skipped` (người dùng chủ động) rồi ghép vào cây.
    func scanSkipped(_ node: SizeNode) {
        let id = ObjectIdentifier(node)
        guard node.skipped, !scanningSkipped.contains(id) else { return }
        scanningSkipped.insert(id)
        let url = node.url
        var options = SpaceScanner.Options.defaults(home: settings.home)
        options.skipPaths = []
        let gen = generation
        Task {
            let r = try? await Task.detached(priority: .userInitiated) {
                try SpaceScanner(options: options).scan(root: url)
            }.value
            scanningSkipped.remove(id)
            guard gen == generation else { return }
            if let r {
                node.replace(with: r.root)
                unreadableCount += r.unreadableCount
                selection = []
                treeVersion += 1
            } else {
                toast.show(L("Couldn't scan this folder", "Không quét được thư mục này"))
            }
        }
    }

    // MARK: Điều hướng

    /// Chuỗi node từ gốc tới `current`.
    var chain: [SizeNode] {
        var out: [SizeNode] = []
        var n = current
        while let node = n { out.append(node); n = node.parent }
        return out.reversed()
    }

    func open(_ node: SizeNode) {
        guard node.kind == .directory, !node.skipped, !node.isUnreadable else { return }
        current = node
        selection = []
    }

    var canGoUp: Bool { current?.parent != nil }

    func up() {
        guard let parent = current?.parent else { return }
        current = parent
        selection = []
    }

    func jump(to node: SizeNode) {
        current = node
        selection = []
    }

    func markStale() {
        if result != nil { isStale = true }
    }

    // MARK: Chuyển vào Thùng rác

    var selectedNodes: [SizeNode] {
        (current?.children ?? []).filter { selection.contains(ObjectIdentifier($0)) }
    }

    /// Mục bị PathGuard chặn (ngoài home / ổ ngoài) vẫn hiện nhưng không xoá được.
    func canTrash(_ node: SizeNode) -> Bool {
        node.isTrashable && !node.skipped && PathGuard(home: settings.home).isAllowed(node.url)
    }

    var canTrashSelection: Bool {
        let nodes = selectedNodes
        return !isBusy && !nodes.isEmpty && nodes.allSatisfy(canTrash)
    }

    func trashSelection() {
        guard canTrashSelection else { return }
        let nodes = selectedNodes
        let reason = L("Space Map", "Bản đồ dung lượng")
        let entries = nodes.map { (url: $0.url, size: $0.size) }
        pendingTrash = nodes
        isBusy = true
        Task {
            let candidates = await Task.detached(priority: .userInitiated) {
                entries.compactMap { e -> Candidate? in
                    guard let fp = FileFingerprint.read(from: e.url) else { return nil }
                    return Candidate(url: e.url, size: e.size, fingerprint: fp, reason: reason, reasonKind: .other,
                                     lastUsed: nil, preselected: true)
                }
            }.value
            isBusy = false
            if candidates.isEmpty {
                pendingTrash = []
                toast.show(L("Nothing to move", "Không có gì để chuyển"))
            } else {
                confirmCandidates = candidates
            }
        }
    }

    func cancelConfirm() {
        confirmCandidates = nil
        pendingTrash = []
    }

    func confirmTrash() {
        guard let shown = confirmCandidates else { return }
        confirmCandidates = nil
        let store = history.store
        let home = settings.home
        let title = L("Space Map", "Bản đồ dung lượng")
        isBusy = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                // Đọc lại fingerprint ngay lúc bấm xác nhận.
                let fresh = shown.compactMap { c -> Candidate? in
                    guard let fp = FileFingerprint.read(from: c.url) else { return nil }
                    return Candidate(id: c.id, url: c.url, size: c.size, fingerprint: fp, reason: c.reason,
                                     reasonKind: c.reasonKind, lastUsed: c.lastUsed, preselected: true)
                }
                return Executor(store: store).perform(candidates: fresh, title: title, trasher: FileManagerTrasher(), home: home)
            }.value
            finishTrash(result)
        }
    }

    private func finishTrash(_ result: PerformResult) {
        isBusy = false
        let doneURLs = Set(result.outcomes.filter { $0.status == .done }.map { $0.url.standardizedFileURL.path })
        for node in pendingTrash where doneURLs.contains(node.url.standardizedFileURL.path) {
            node.removeFromParent()
        }
        pendingTrash = []
        selection = []
        treeVersion += 1
        let done = doneURLs.count
        let problems = result.outcomes.compactMap(Problem.from)
        var message = done == 0 ? L("Nothing was moved", "Chưa chuyển được mục nào") : movedToTrashText(done)
        if !problems.isEmpty {
            message += L(" · \(problems.count) skipped or failed", " · \(problems.count) mục bị bỏ qua hoặc lỗi")
        }
        if let e = result.journalError {
            message += L(" · history could not be saved: \(e)", " · không ghi được lịch sử: \(e)")
        }
        history.reload()
        toast.show(message, undoBatch: done > 0 ? result.batch : nil, problems: problems)
        onChanged?()
    }
}
