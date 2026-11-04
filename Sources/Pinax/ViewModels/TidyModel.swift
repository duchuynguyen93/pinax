import Foundation
import Observation
import PinaxCore

@MainActor @Observable
final class TidyModel {
    let settings: AppSettings
    let history: HistoryModel
    let toast: ToastModel

    private(set) var plan: TidyPlan?
    private(set) var isLoading = false
    private(set) var isPerforming = false
    /// Nhóm người dùng đã bỏ tick.
    var disabledKinds: Set<FileKind> = []
    private var loadGeneration = 0
    /// Gọi sau khi Tidy xong để Smart Clean cập nhật dung lượng.
    var onChanged: (() -> Void)?

    init(settings: AppSettings, history: HistoryModel, toast: ToastModel) {
        self.settings = settings
        self.history = history
        self.toast = toast
    }

    var enabledKinds: Set<FileKind> { Set(FileKind.allCases).subtracting(disabledKinds) }
    var filtered: TidyPlan? { plan?.filtered(kinds: enabledKinds) }
    var folder: URL { settings.clean.tidyFolder }
    var canTidy: Bool { !isPerforming && !isLoading && !(filtered?.tidyMoves.isEmpty ?? true) }

    func toggleKind(_ k: FileKind) {
        if disabledKinds.contains(k) { disabledKinds.remove(k) } else { disabledKinds.insert(k) }
    }

    func refresh() {
        loadGeneration += 1
        let gen = loadGeneration
        isLoading = true
        let folder = folder, home = settings.home
        Task {
            let p = await Task.detached(priority: .userInitiated) {
                TidyPlanner.plan(folder: folder, now: Date(), home: home)
            }.value
            guard gen == loadGeneration else { return }
            plan = p
            isLoading = false
        }
    }

    func tidy() {
        guard canTidy, let p = filtered else { return }
        let store = history.store
        let home = settings.home
        let name = folder.lastPathComponent
        let title = L("Tidy \(name)", "Sắp xếp \(name)")
        let moves = p.moves, dirs = p.createDirs
        isPerforming = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Executor(store: store).perform(moves: moves, createDirs: dirs, title: title, home: home)
            }.value
            isPerforming = false
            history.reload()
            let sources = Set(moves.map(\.from))
            let moved = result.outcomes.filter { $0.status == .done && sources.contains($0.url) }.count
            let problems = result.outcomes.compactMap(Problem.from)
            var message = L("Tidied \(itemsText(moved))", "Đã sắp xếp \(itemsText(moved))")
            if !problems.isEmpty {
                message += L(" · \(problems.count) skipped or failed", " · \(problems.count) mục bị bỏ qua hoặc lỗi")
            }
            if let e = result.journalError {
                message += L(" · history could not be saved: \(e)", " · không ghi được lịch sử: \(e)")
            }
            toast.show(message, undoBatch: result.batch, problems: problems)
            refresh()
            onChanged?()
        }
    }
}
