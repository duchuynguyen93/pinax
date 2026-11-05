import AppKit
import Observation
import PinaxCore

/// Cách hiển thị thư mục.
enum BrowserViewMode: String { case list, icons }

/// Ba cỡ của icon view: cạnh icon (pt) và bề rộng ô.
enum IconSize: Int, CaseIterable {
    case small, medium, large
    var points: CGFloat { [48, 80, 128][rawValue] }
    var cellWidth: CGFloat { points + 40 }
    var cellHeight: CGFloat { points + 58 }
    var larger: IconSize? { IconSize(rawValue: rawValue + 1) }
    var smaller: IconSize? { IconSize(rawValue: rawValue - 1) }
}

enum BrowseError: Equatable {
    case denied
    case failed(String)
}

/// Mỗi cửa sổ / tab giữ một `BrowserModel`: thư mục đang xem, lịch sử, danh sách và vùng chọn.
@MainActor @Observable
final class BrowserModel {
    let prefs: BrowserPrefs
    let toast: ToastModel
    let history: HistoryModel
    let home: URL
    /// Git ở path bar (chỉ đọc).
    let git = GitStatusModel()

    private(set) var folder: URL
    /// Khác nil → vùng nội dung hiện màn M1 tương ứng thay vì thư mục.
    private(set) var pinax: SidebarSection?
    private(set) var items: [FileItem] = []
    /// Tăng mỗi khi `items` đổi → bảng nạp lại.
    private(set) var generation = 0
    /// Tăng khi sang thư mục mới → bảng cuộn lên đầu.
    private(set) var resetToken = 0
    /// Tăng khi cần cuộn tới mục đang chọn (vd. đi tới đường dẫn của một file).
    private(set) var revealToken = 0
    /// Đường dẫn các mục đang chọn.
    var selection: Set<String> = []
    private(set) var error: BrowseError?
    private(set) var isLoading = false
    private(set) var availableBytes: Int64?
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []
    var pathEditing = false
    var viewMode: BrowserViewMode {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: Self.viewModeKey) }
    }
    var iconSize: IconSize {
        didSet { UserDefaults.standard.set(iconSize.rawValue, forKey: Self.iconSizeKey) }
    }
    /// Đang xem trước (Quick Look) file nào; `quickLookURLs` là danh sách điều hướng được bằng phím mũi tên.
    var quickLookURL: URL?
    private(set) var quickLookURLs: [URL] = []
    /// Tăng khi cần bắt đầu đổi tên tại chỗ `pendingRename`.
    private(set) var renameToken = 0
    /// Đường dẫn mục cần đổi tên; view xử lý khi mục đã có trong danh sách rồi xoá.
    @ObservationIgnored var pendingRename: String?
    @ObservationIgnored weak var window: NSWindow?
    /// Kích thước thư mục tính nền, dùng chung cho list và icon view.
    @ObservationIgnored let folderSizes = FolderSizeStore()

    static let viewModeKey = "pinax.browser.viewMode"
    static let iconSizeKey = "pinax.browser.iconSize"

    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var sortTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var started = false
    /// Mốc bắt đầu điều hướng, để in thời gian tới lúc bảng nạp xong (DEBUG).
    @ObservationIgnored var navStart: UInt64?
    /// PINAX_PERF_LOG=1: in thời gian từ lúc điều hướng tới lúc bảng nạp xong ra stderr (cả bản release).
    static let perfLog = ProcessInfo.processInfo.environment["PINAX_PERF_LOG"] == "1"

    init(prefs: BrowserPrefs, toast: ToastModel, history: HistoryModel, home: URL) {
        self.prefs = prefs
        self.toast = toast
        self.history = history
        self.home = home
        folder = FileManager.default.homeDirectoryForCurrentUser
        let ud = UserDefaults.standard
        viewMode = BrowserViewMode(rawValue: ud.string(forKey: Self.viewModeKey) ?? "") ?? .list
        iconSize = IconSize(rawValue: ud.object(forKey: Self.iconSizeKey) as? Int ?? 1) ?? .medium
    }

    // MARK: Trạng thái dẫn xuất

    var title: String {
        pinax?.title ?? FileManager.default.displayName(atPath: folder.path)
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }
    var canGoUp: Bool { folder.path != "/" }

    var selectedItems: [FileItem] { items.filter { selection.contains($0.url.path) } }

    // MARK: Khởi động

    /// Mở thư mục đầu tiên (một lần). File → mở thư mục chứa và chọn file; không tồn tại → cha gần nhất.
    func start(path: String) {
        guard !started else { return }
        started = true
        if Self.perfLog { navStart = DispatchTime.now().uptimeNanoseconds }
        let url = URL(fileURLWithPath: path)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            if isDir.boolValue {
                folder = Self.normalized(url)
            } else {
                folder = Self.normalized(url.deletingLastPathComponent())
                selection = [url.path]
                revealToken += 1
            }
        } else {
            folder = FolderResolve.nearestExistingFolder(url)
        }
        beginLoad(reset: true)
        installWatcher()
        git.folderChanged(folder)
    }

    // MARK: Điều hướng

    func navigate(to url: URL, select: String? = nil) {
        pathEditing = false
        pinax = nil
        let target = Self.normalized(url)
        if target.path == folder.path {
            if let select { selection = [select]; revealToken += 1 }
            beginLoad(reset: false)
            return
        }
        backStack.append(folder)
        forwardStack.removeAll()
        move(to: target, select: select)
    }

    func back() {
        guard let target = backStack.popLast() else { return }
        forwardStack.append(folder)
        pinax = nil
        move(to: target, select: nil)
    }

    func forward() {
        guard let target = forwardStack.popLast() else { return }
        backStack.append(folder)
        pinax = nil
        move(to: target, select: nil)
    }

    /// Lên thư mục cha và chọn thư mục vừa rời.
    func up() {
        guard canGoUp else { return }
        navigate(to: folder.deletingLastPathComponent(), select: folder.path)
    }

    func showPinax(_ section: SidebarSection) {
        folderSizes.cancelAll()
        pathEditing = false
        pinax = section
    }

    private func move(to target: URL, select: String?) {
        if Self.perfLog { navStart = DispatchTime.now().uptimeNanoseconds }
        folderSizes.cancelAll()
        quickLookURL = nil
        pendingRename = nil
        folder = target
        selection = select.map { [$0] } ?? []
        if select != nil { revealToken += 1 }
        beginLoad(reset: true)
        installWatcher()
        git.folderChanged(folder)
    }

    /// Gõ đường dẫn ở ⌘L. false nếu không tồn tại (đứng yên).
    func go(toPath raw: String) -> Bool {
        var p = raw.trimmingCharacters(in: .whitespaces)
        guard !p.isEmpty else { return false }
        p = (p as NSString).expandingTildeInPath
        if !p.hasPrefix("/") { p = folder.appendingPathComponent(p).path }
        let url = URL(fileURLWithPath: p).standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { return false }
        if isDir.boolValue {
            navigate(to: url)
        } else {
            navigate(to: url.deletingLastPathComponent(), select: url.path)
        }
        return true
    }

    // MARK: Kiểu xem, Quick Look

    func zoomIn() { if viewMode == .icons, let s = iconSize.larger { iconSize = s } }
    func zoomOut() { if viewMode == .icons, let s = iconSize.smaller { iconSize = s } }

    /// Space: mở / đóng xem trước. Nhiều mục chọn → duyệt trong phần chọn; một mục → duyệt cả thư mục.
    func toggleQuickLook() {
        if quickLookURL != nil { quickLookURL = nil; return }
        let sel = selectedItems
        guard let first = sel.first else { return }
        quickLookURLs = sel.count > 1 ? sel.map(\.url) : items.map(\.url)
        quickLookURL = first.url
    }

    // MARK: Mở mục

    func openSelection() { open(selectedItems) }

    func open(_ targets: [FileItem]) {
        if targets.count == 1, let dir = Self.folderTarget(targets[0]) {
            navigate(to: dir)
            return
        }
        for item in targets where Self.folderTarget(item) == nil {
            NSWorkspace.shared.open(item.url)
        }
    }

    /// Đích thư mục nếu mục này đi vào được: thư mục thường, hoặc symlink / alias trỏ tới thư mục (không phải package).
    private static func folderTarget(_ item: FileItem) -> URL? {
        if item.isNavigableFolder { return item.url }
        guard item.isSymlink || item.isAlias else { return nil }
        let target: URL
        if item.isAlias {
            guard let r = try? URL(resolvingAliasFileAt: item.url, options: [.withoutUI, .withoutMounting]) else { return nil }
            target = r
        } else {
            target = item.url.resolvingSymlinksInPath()
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue,
              !NSWorkspace.shared.isFilePackage(atPath: target.path) else { return nil }
        return target
    }

    // MARK: Nạp danh sách

    func reload() { beginLoad(reset: false) }

    /// Cho extension `BrowserActions` (cùng module) nạp lại và yêu cầu đổi tên.
    func reloadAfterOperation(select paths: Set<String>? = nil, rename: String? = nil) {
        if let paths { selection = paths; revealToken += 1 }
        if let rename { requestRename(rename) }
        beginLoad(reset: false)
    }

    func requestRename(_ path: String) {
        pendingRename = path
        renameToken += 1
    }

    private struct Listing: Sendable {
        let items: [FileItem]
        let available: Int64?
        let sort: FileSort
    }

    private static func normalized(_ url: URL) -> URL {
        URL(fileURLWithPath: url.standardizedFileURL.path, isDirectory: true)
    }

    /// Liệt kê + sắp xếp ngoài main thread. Tạo task ngay (không đợi main actor rảnh): lúc mở cửa sổ mới
    /// main còn bận dựng giao diện ~150 ms, việc đọc thư mục chạy song song với khoảng đó.
    private nonisolated static func listingTask(_ url: URL, hidden: Bool, sort: FileSort) -> Task<Listing, Error> {
        Task.detached(priority: .userInitiated) { () throws -> Listing in
            let t0 = DispatchTime.now().uptimeNanoseconds
            let raw = try await DirectoryLister.list(url, showHidden: hidden)
            try Task.checkCancellation()
            let t1 = DispatchTime.now().uptimeNanoseconds
            let sorted = sort.sorted(raw)
            if perfLog {
                let t2 = DispatchTime.now().uptimeNanoseconds
                FileHandle.standardError.write(Data(String(format: "[Pinax perf]   list %.1f ms, sort %.1f ms\n",
                    Double(t1 - t0) / 1e6, Double(t2 - t1) / 1e6).utf8))
            }
            let cap = (try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
                .volumeAvailableCapacityForImportantUsage
            return Listing(items: sorted, available: cap, sort: sort)
        }
    }

    private func beginLoad(reset: Bool) {
        listTask?.cancel()
        isLoading = true
        let url = folder
        let work = Self.listingTask(url, hidden: prefs.showHidden, sort: prefs.sort)
        listTask = Task { [weak self] in
            let result: Result<Listing, Error>
            do {
                result = .success(try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() })
            } catch { result = .failure(error) }
            guard let self, !Task.isCancelled, self.folder.path == url.path else { return }
            self.perfMark("listing back on main")
            self.finish(result, reset: reset)
        }
    }

    func perfMark(_ label: String) {
        guard let start = navStart else { return }
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        FileHandle.standardError.write(Data(String(format: "[Pinax perf]   %@ %.1f ms\n", label, ms).utf8))
    }

    private func finish(_ result: Result<Listing, Error>, reset: Bool) {
        isLoading = false
        switch result {
        case .success(let listing):
            items = listing.items
            availableBytes = listing.available
            error = nil
            selection.formIntersection(Set(listing.items.map { $0.url.path }))
            folderSizes.request(listing.items)
            if listing.sort != prefs.sort { resort() }
        case .failure(let err):
            if err is CancellationError { return }
            guard FileManager.default.fileExists(atPath: folder.path) else {
                recoverFromMissingFolder()
                return
            }
            items = []
            availableBytes = nil
            selection = []
            error = Self.classify(err)
        }
        generation += 1
        if reset { resetToken += 1 }
    }

    private static func classify(_ err: Error) -> BrowseError {
        let ns = err as NSError
        if ns.domain == NSCocoaErrorDomain, ns.code == NSFileReadNoPermissionError { return .denied }
        if ns.domain == NSPOSIXErrorDomain, ns.code == Int(EPERM) || ns.code == Int(EACCES) { return .denied }
        if let under = ns.userInfo[NSUnderlyingErrorKey] as? NSError, under.domain == NSPOSIXErrorDomain,
           under.code == Int(EPERM) || under.code == Int(EACCES) { return .denied }
        return .failed(err.localizedDescription)
    }

    /// Sắp xếp lại danh sách hiện có (đổi cột / bật tắt "thư mục trước").
    func resort() {
        sortTask?.cancel()
        let current = items, sort = prefs.sort
        sortTask = Task { [weak self] in
            let sorted = await Task.detached(priority: .userInitiated) { sort.sorted(current) }.value
            guard let self, !Task.isCancelled else { return }
            self.items = sorted
            self.generation += 1
        }
    }

    // MARK: Theo dõi thay đổi

    private func installWatcher() {
        watcher?.stop()
        watcher = DirectoryWatcher(url: folder) { [weak self] event in
            Task { @MainActor in
                guard let self else { return }
                switch event {
                case .changed:
                    self.beginLoad(reset: false)
                    self.git.refresh(self.folder)
                case .vanished: self.recoverFromMissingFolder()
                }
            }
        }
    }

    /// Thư mục đang xem biến mất → sang thư mục cha gần nhất còn tồn tại.
    private func recoverFromMissingFolder() {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue {
            installWatcher() // báo nhầm (vd. đổi tên rồi đổi lại) → chỉ nạp lại
            beginLoad(reset: false)
            return
        }
        let missing = folder.lastPathComponent
        let target = FolderResolve.nearestExistingFolder(folder)
        toast.show(L("“\(missing)” is no longer available. Went to “\(target.lastPathComponent)”.",
                     "“\(missing)” không còn nữa. Đã chuyển tới “\(target.lastPathComponent)”."))
        navigate(to: target)
    }
}
