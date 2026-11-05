import Foundation
import Observation
import PinaxCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case smartClean, downloads, history
    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartClean: L("Smart Clean", "Dọn dẹp thông minh")
        case .downloads: L("Tidy Downloads", "Sắp xếp Downloads")
        case .history: L("History", "Lịch sử")
        }
    }

    var symbol: String {
        switch self {
        case .smartClean: "sparkles"
        case .downloads: "arrow.down.circle"
        case .history: "clock.arrow.circlepath"
        }
    }
}

/// Gom các model dùng chung; sở hữu luồng hoàn tác để toast / History / ⌘Z dùng chung một đường.
@MainActor @Observable
final class AppEnvironment {
    let settings = AppSettings()
    let toast = ToastModel()
    let history: HistoryModel
    let smart: SmartCleanModel
    let tidy: TidyModel
    let prefs = BrowserPrefs()
    let favorites = FavoritesModel()
    let volumes: VolumesModel
    let transfers: TransferQueue

    init() {
        let history = HistoryModel(store: JournalStore())
        self.history = history
        volumes = VolumesModel(toast: toast)
        transfers = TransferQueue(history: history, toast: toast) { [settings] in settings.home }
        smart = SmartCleanModel(settings: settings, history: history, toast: toast)
        tidy = TidyModel(settings: settings, history: history, toast: toast)
        toast.undoHandler = { [weak self] batch in self?.undo(batch) }
        tidy.onChanged = { [weak self] in self?.smart.refreshStorage() }
    }

    func undo(_ batch: Batch) {
        guard !history.isUndoing, !batch.undone else { return }
        Task {
            let outcomes = await history.undo(batch)
            let done = outcomes.filter { $0.status == .done }.count
            let problems = outcomes.compactMap(Problem.from)
            var message = L("Undone: restored \(done) of \(outcomes.count)", "Đã hoàn tác: khôi phục \(done)/\(outcomes.count)")
            if !problems.isEmpty {
                message += L(" · \(problems.count) skipped or failed", " · \(problems.count) mục bị bỏ qua hoặc lỗi")
            }
            toast.show(message, problems: problems)
            smart.refreshStorage()
            tidy.refresh()
        }
    }

    func undoLatest() {
        if let b = history.latestUndoable { undo(b) }
    }

    func tidyNow() {
        guard tidy.canTidy else { return }
        tidy.tidy()
    }
}
