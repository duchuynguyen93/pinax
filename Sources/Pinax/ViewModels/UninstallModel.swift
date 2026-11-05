import AppKit
import Foundation
import Observation
import PinaxCore

/// Một app trong danh sách (đã lọc bỏ app hệ thống / com.apple.* / Pinax).
struct UninstallApp: Identifiable, Hashable {
    let app: InstalledApp
    let version: String?
    var id: String { app.url.path }
    var url: URL { app.url }
    var name: String { app.name }
}

/// Một dòng trong danh sách "app để lại gì": chính app hoặc một mục trong ~/Library.
struct FootprintRow: Identifiable, Hashable {
    let url: URL
    /// Thư mục cha tính từ ~/Library; rỗng với chính app.
    let location: String
    /// nil = chính app bundle.
    let match: FootprintMatch?
    let preselected: Bool
    var size: Int64
    var id: String { url.path }
    var isApp: Bool { match == nil }
}

enum UninstallSort: String, CaseIterable, Identifiable {
    case name, size, lastUsed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .name: L("Name", "Tên")
        case .size: L("Size", "Dung lượng")
        case .lastUsed: L("Last used", "Dùng lần cuối")
        }
    }
}

@MainActor @Observable
final class UninstallModel {
    let settings: AppSettings
    let history: HistoryModel
    let toast: ToastModel
    /// Gọi sau khi gỡ xong để Smart Clean cập nhật dung lượng.
    var onChanged: (() -> Void)?

    private(set) var apps: [UninstallApp] = []
    private(set) var isLoadingApps = false
    private(set) var sizes: [String: Int64] = [:]
    private(set) var lastUsed: [String: Date] = [:]
    var search = ""
    var sort: UninstallSort = .name {
        didSet { if sort != .name { requestMeta(apps) } }
    }

    private(set) var selected: UninstallApp?
    private(set) var rows: [FootprintRow] = []
    private(set) var ticked: Set<String> = []
    private(set) var sharedTeam = false
    private(set) var isLoadingFootprint = false
    private(set) var isBusy = false

    // Trạng thái hộp thoại (view gắn vào alert / sheet).
    var showQuitAlert = false
    var showSystemOwnedAlert = false
    var confirmCandidates: [Candidate]?

    private var metaRequested: Set<String> = []
    private var footprintGeneration = 0
    private var loadedOnce = false
    private var qaApp: URL? = ProcessInfo.processInfo.environment["PINAX_QA_UNINSTALL_APP"].flatMap {
        $0.isEmpty ? nil : URL(fileURLWithPath: $0)
    }

    init(settings: AppSettings, history: HistoryModel, toast: ToastModel) {
        self.settings = settings
        self.history = history
        self.toast = toast
    }

    // MARK: Danh sách app

    var visibleApps: [UninstallApp] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let filtered = q.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
        switch sort {
        case .name:
            return filtered
        case .size:
            return filtered.sorted { (sizes[$0.id] ?? -1) > (sizes[$1.id] ?? -1) }
        case .lastUsed:
            return filtered.sorted { (lastUsed[$0.id] ?? .distantPast) > (lastUsed[$1.id] ?? .distantPast) }
        }
    }

    func loadAppsIfNeeded() {
        if !loadedOnce { loadApps() }
    }

    func loadApps() {
        guard !isLoadingApps else { return }
        isLoadingApps = true
        let roots = settings.applicationRoots
        Task {
            let list = await Task.detached(priority: .userInitiated) { UninstallWork.listApps(roots: roots) }.value
            apps = list
            isLoadingApps = false
            loadedOnce = true
            if let selected, !list.contains(where: { $0.id == selected.id }), !FileManager.default.fileExists(atPath: selected.url.path) {
                clearSelection()
            }
            if sort != .name { requestMeta(list) }
            if let qa = qaApp {
                qaApp = nil
                select(url: qa)
            }
        }
    }

    /// Tính size + lần dùng cuối ở nền, tuần tự, mỗi app một lần.
    func requestMeta(_ list: [UninstallApp]) {
        let todo = list.filter { metaRequested.insert($0.id).inserted }
        guard !todo.isEmpty else { return }
        Task.detached(priority: .utility) { [weak self] in
            let weakSelf = self
            let provider = SpotlightLastUsedProvider()
            for a in todo {
                let size = (try? SizeCalculator.allocatedSize(of: a.url)) ?? 0
                let used = provider.info(for: a.url).lastUsed
                await MainActor.run {
                    weakSelf?.sizes[a.id] = size
                    if let used { weakSelf?.lastUsed[a.id] = used }
                }
            }
        }
    }

    // MARK: Chọn app

    func select(_ app: UninstallApp?) {
        guard let app else { clearSelection(); return }
        footprintGeneration += 1
        let gen = footprintGeneration
        selected = app
        rows = []
        ticked = []
        sharedTeam = false
        isLoadingFootprint = true
        let others = apps.map(\.app).filter { $0.url.path != app.id }
        let library = settings.home.appendingPathComponent("Library", isDirectory: true)
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                UninstallWork.footprint(of: app.app, others: others, library: library)
            }.value
            guard gen == footprintGeneration else { return }
            rows = result.rows
            ticked = Set(result.rows.filter(\.preselected).map(\.id))
            sharedTeam = result.sharedTeam
            sizes[app.id] = result.rows.first?.size
            isLoadingFootprint = false
        }
    }

    /// Chọn theo đường dẫn (thả .app vào view, QA). App hệ thống bị từ chối bằng toast.
    func select(url: URL) {
        if let known = apps.first(where: { $0.id == url.path }) { select(known); return }
        Task {
            let found = await Task.detached(priority: .userInitiated) { UninstallWork.makeApp(url: url) }.value
            guard let found else { return }
            if UninstallWork.isProtected(found) {
                toast.show(L("Pinax doesn't uninstall system apps", "Pinax không gỡ app hệ thống"))
            } else {
                select(found)
            }
        }
    }

    func clearSelection() {
        footprintGeneration += 1
        selected = nil
        rows = []
        ticked = []
        isLoadingFootprint = false
    }

    func toggle(_ row: FootprintRow) {
        if ticked.contains(row.id) { ticked.remove(row.id) } else { ticked.insert(row.id) }
    }

    var tickedRows: [FootprintRow] { rows.filter { ticked.contains($0.id) } }
    var tickedBytes: Int64 { tickedRows.reduce(0) { $0 + $1.size } }
    var canUninstall: Bool { selected != nil && !isLoadingFootprint && !isBusy && !ticked.isEmpty }

    // MARK: Gỡ

    private func runningInstances(of app: UninstallApp) -> [NSRunningApplication] {
        guard let id = app.app.bundleID else { return [] }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id).filter { !$0.isTerminated }
    }

    func uninstall() {
        guard canUninstall, let app = selected else { return }
        if runningInstances(of: app).isEmpty { prepareConfirm() } else { showQuitAlert = true }
    }

    /// Nút Quit của alert: terminate, chờ tối đa 5 s.
    func quitAndContinue() {
        guard let app = selected else { return }
        isBusy = true
        runningInstances(of: app).forEach { $0.terminate() }
        Task {
            for _ in 0..<20 {
                if runningInstances(of: app).isEmpty { break }
                try? await Task.sleep(for: .milliseconds(250))
            }
            isBusy = false
            if runningInstances(of: app).isEmpty {
                prepareConfirm()
            } else {
                toast.show(L("\(app.name) is still running", "\(app.name) vẫn đang chạy"))
            }
        }
    }

    /// Dựng candidate (để hiện trong ConfirmSheet) ở nền.
    private func prepareConfirm() {
        guard let app = selected else { return }
        let chosen = tickedRows
        let reason = L("Uninstall \(app.name)", "Gỡ \(app.name)")
        isBusy = true
        Task {
            let candidates = await Task.detached(priority: .userInitiated) {
                UninstallWork.candidates(rows: chosen, reason: reason)
            }.value
            isBusy = false
            if candidates.isEmpty {
                toast.show(L("Nothing to move", "Không có gì để chuyển"))
            } else {
                confirmCandidates = candidates
            }
        }
    }

    func cancelConfirm() { confirmCandidates = nil }

    func confirmUninstall() {
        guard let app = selected, let shown = confirmCandidates else { return }
        confirmCandidates = nil
        let store = history.store
        let home = settings.home
        let title = L("Uninstall \(app.name)", "Gỡ \(app.name)")
        isBusy = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                // Đọc lại fingerprint ngay lúc bấm xác nhận.
                let fresh = UninstallWork.refreshed(shown)
                return Executor(store: store).perform(candidates: fresh, title: title, trasher: FileManagerTrasher(), home: home)
            }.value
            finish(result, app: app)
        }
    }

    private func finish(_ result: PerformResult, app: UninstallApp) {
        isBusy = false
        let done = result.outcomes.filter { $0.status == .done }.count
        let problems = result.outcomes.compactMap(Problem.from)
        var message = done == 0 ? L("Nothing was moved", "Chưa chuyển được mục nào") : movedToTrashText(done)
        if !problems.isEmpty {
            message += L(" · \(problems.count) skipped or failed", " · \(problems.count) mục bị bỏ qua hoặc lỗi")
        }
        if let e = result.journalError {
            message += L(" · history could not be saved: \(e)", " · không ghi được lịch sử: \(e)")
        }
        let appPath = app.url.resolvingSymlinksInPath().standardizedFileURL.path
        if result.outcomes.contains(where: { o in
            if case .failed = o.status { return o.url.resolvingSymlinksInPath().standardizedFileURL.path == appPath }
            return false
        }) {
            showSystemOwnedAlert = true
        }
        history.reload()
        toast.show(message, undoBatch: done > 0 ? result.batch : nil, problems: problems)
        clearSelection()
        loadApps()
        onChanged?()
    }
}

/// Việc đọc đĩa / chữ ký, chạy ngoài main thread.
enum UninstallWork {
    static func isProtected(_ a: UninstallApp) -> Bool {
        PathGuard.isProtectedApp(bundleID: a.app.bundleID) || a.url.path.hasPrefix("/System/")
    }

    static func makeApp(url: URL) -> UninstallApp? {
        guard url.pathExtension.lowercased() == "app" else { return nil }
        let info = Bundle(url: url)?.infoDictionary
        let name = (info?["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        return UninstallApp(app: InstalledApp(url: url, bundleID: info?["CFBundleIdentifier"] as? String, name: name),
                            version: info?["CFBundleShortVersionString"] as? String)
    }

    static func listApps(roots: [URL]) -> [UninstallApp] {
        FileSystemInstalledApps(roots: roots).installedApps()
            .compactMap { makeApp(url: $0.url) }
            .filter { !isProtected($0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func footprint(of app: InstalledApp, others: [InstalledApp], library: URL) -> (rows: [FootprintRow], sharedTeam: Bool) {
        let team = TeamID.of(appURL: app.url)
        var items = AppFootprint.items(for: app, teamID: team, otherAppsWithSameTeam: false, library: library)
        var shared = false
        // Chỉ kiểm team của app khác khi thật sự có Group Containers theo team.
        if let team, items.contains(where: { $0.match == .teamGroup }) {
            shared = others.contains { TeamID.of(appURL: $0.url) == team }
            if shared { items = AppFootprint.items(for: app, teamID: team, otherAppsWithSameTeam: true, library: library) }
        }
        var rows = [FootprintRow(url: app.url, location: "", match: nil, preselected: true,
                                 size: (try? SizeCalculator.allocatedSize(of: app.url)) ?? 0)]
        for i in items {
            rows.append(FootprintRow(url: i.url, location: i.location, match: i.match, preselected: i.preselected,
                                     size: (try? SizeCalculator.allocatedSize(of: i.url)) ?? 0))
        }
        return (rows, shared)
    }

    static func candidates(rows: [FootprintRow], reason: String) -> [Candidate] {
        rows.compactMap { r in
            guard let fp = FileFingerprint.read(from: r.url) else { return nil }
            return Candidate(url: r.url, size: r.size, fingerprint: fp, reason: reason, reasonKind: .other,
                             lastUsed: nil, preselected: true)
        }
    }

    static func refreshed(_ list: [Candidate]) -> [Candidate] {
        list.compactMap { c in
            guard let fp = FileFingerprint.read(from: c.url) else { return nil }
            return Candidate(id: c.id, url: c.url, size: c.size, fingerprint: fp, reason: c.reason,
                             reasonKind: c.reasonKind, lastUsed: c.lastUsed, preselected: true)
        }
    }
}
