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

/// Phạm vi tìm: lọc danh sách đang xem, hoặc tìm đệ quy trong thư mục con.
enum SearchScope: String, CaseIterable {
    case folder, subfolders
    var title: String {
        switch self {
        case .folder: L("This Folder", "Thư mục này")
        case .subfolders: L("Subfolders", "Thư mục con")
        }
    }
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
    let transfers: TransferQueue
    let home: URL
    /// Gắn khi dựng cửa sổ; menu "Analyze Size" dùng để mở Space Map.
    @ObservationIgnored weak var spaceMap: SpaceMapModel?
    /// Git ở path bar (chỉ đọc).
    let git = GitStatusModel()

    private(set) var folder: URL
    /// Khác nil → vùng nội dung hiện màn M1 tương ứng thay vì thư mục.
    private(set) var pinax: SidebarSection?
    /// Cái đang hiển thị: danh sách thư mục, đã lọc / thay bằng kết quả khi đang tìm.
    private(set) var items: [FileItem] = []
    /// Tăng mỗi khi `items` đổi → bảng nạp lại.
    private(set) var generation = 0
    /// Tăng khi sang thư mục mới → bảng cuộn lên đầu.
    private(set) var resetToken = 0
    /// Tăng khi cần cuộn tới mục đang chọn (vd. đi tới đường dẫn của một file).
    private(set) var revealToken = 0
    /// Đường dẫn các mục đang chọn.
    var selection: Set<String> = []
    /// Khác nil → đang hiện sheet đổi tên hàng loạt cho các URL này (theo thứ tự hiển thị).
    var batchRenameItems: [URL]?
    /// QA: mở sheet ở kiểu Format với base "Photo".
    var batchRenameQAPreset: String?
    private(set) var error: BrowseError?
    private(set) var isLoading = false
    private(set) var availableBytes: Int64?
    private(set) var backStack: [URL] = []
    private(set) var forwardStack: [URL] = []
    var pathEditing = false {
        didSet { if pathEditing { onActivate?() } }
    }
    var viewMode: BrowserViewMode {
        didSet { if !applyingPreset { UserDefaults.standard.set(viewMode.rawValue, forKey: Self.viewModeKey) } }
    }
    @ObservationIgnored private var applyingPreset = false

    /// Kiểu xem đến từ workspace: chỉ áp cho pane này, không đổi mặc định của app.
    func applyPresetViewMode(_ mode: BrowserViewMode) {
        applyingPreset = true
        viewMode = mode
        applyingPreset = false
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
    /// Mục vừa chép / nhân bản cần chọn ngay khi chúng xuất hiện trong danh sách (watcher nạp lại sau job).
    @ObservationIgnored var pendingSelect: Set<String> = []
    @ObservationIgnored weak var window: NSWindow?
    /// Cửa sổ chứa pane này (nil khi chưa gắn); dùng cho dual pane.
    @ObservationIgnored weak var windowModel: WindowModel?
    /// Pane này vừa được chọn làm pane active (focus bảng, bấm path bar, ⌘L...). WindowModel gắn vào.
    @ObservationIgnored var onActivate: (() -> Void)?
    /// Tab / ⇧Tab trong bảng khi đang dual → chuyển sang pane kia.
    @ObservationIgnored var onSwitchPane: (() -> Void)?
    /// Bảng / lưới đang hiển thị của pane (list hoặc icon view đặt vào), để chuyển focus tới.
    @ObservationIgnored weak var contentView: NSView?
    /// Kích thước thư mục tính nền, dùng chung cho list và icon view.
    @ObservationIgnored let folderSizes = FolderSizeStore()

    static let viewModeKey = "pinax.browser.viewMode"
    static let iconSizeKey = "pinax.browser.iconSize"

    // MARK: Tìm kiếm

    /// Câu tìm (ô tìm trên toolbar). Đổi → lọc ngay (This Folder) hoặc tìm lại sau 200 ms (Subfolders).
    var searchText = "" {
        didSet { if !silentSearchChange, searchText != oldValue { searchChanged() } }
    }
    var searchScope: SearchScope = .folder {
        didSet { if !silentSearchChange, searchScope != oldValue { searchChanged() } }
    }
    /// Đang tìm bằng engine (Spotlight / fts) chưa xong.
    private(set) var searchRunning = false
    /// Kết quả Subfolders bị cắt ở 5 000.
    private(set) var searchTruncated = false
    private(set) var searchMatcher = NameMatcher("")
    /// Số kết quả cắt tối đa.
    nonisolated static let searchLimit = 5000
    var isSearching: Bool { !searchMatcher.isEmpty }
    /// Đang xem kết quả đệ quy: không có "thư mục hiện tại" để tạo / dán / thả vào.
    var inSubfolderSearch: Bool { isSearching && searchScope == .subfolders }
    /// Thả vào nền bảng / lưới = thả vào thư mục đang xem; không được khi đang xem kết quả đệ quy.
    var backgroundDropAllowed: Bool { !inSubfolderSearch }

    @ObservationIgnored private var listed: [FileItem] = []
    @ObservationIgnored private var results: [FileItem] = []
    @ObservationIgnored private var listedVersion = 0
    @ObservationIgnored private var resultsVersion = 0
    @ObservationIgnored private var silentSearchChange = false
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var spotlight: SpotlightSearch?
    /// Tăng mỗi khi huỷ / bắt đầu lại, để bỏ kết quả của lần tìm cũ.
    @ObservationIgnored private var searchEpoch = 0
    @ObservationIgnored private var usingSpotlight = false
    @ObservationIgnored private var searchShowHidden = false
    @ObservationIgnored private var spotlightBuilding = false
    @ObservationIgnored private var spotlightPending: [URL]?
    @ObservationIgnored private var spotlightFinished = false
    @ObservationIgnored private var searchRoot = ""
    @ObservationIgnored private var searchRootResolved = ""

    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var sortTask: Task<Void, Never>?
    @ObservationIgnored private var watcher: DirectoryWatcher?
    @ObservationIgnored private var started = false
    /// Mốc bắt đầu điều hướng, để in thời gian tới lúc bảng nạp xong (DEBUG).
    @ObservationIgnored var navStart: UInt64?
    /// PINAX_PERF_LOG=1: in thời gian từ lúc điều hướng tới lúc bảng nạp xong ra stderr (cả bản release).
    nonisolated static let perfLog = ProcessInfo.processInfo.environment["PINAX_PERF_LOG"] == "1"

    init(prefs: BrowserPrefs, toast: ToastModel, history: HistoryModel, transfers: TransferQueue, home: URL) {
        self.prefs = prefs
        self.toast = toast
        self.history = history
        self.transfers = transfers
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

    /// Pane đang active trong cửa sổ (đơn thì luôn true).
    var isActivePane: Bool { windowModel.map { $0.active === self } ?? true }

    var selectedItems: [FileItem] { items.filter { selection.contains($0.url.path) } }

    /// Đưa focus bàn phím vào bảng / lưới của pane.
    func focusContent() {
        guard let v = contentView, let w = v.window else { return }
        w.makeFirstResponder(v)
    }

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

    /// Mở Space Map và quét `url`.
    func analyzeSize(_ url: URL) {
        showPinax(.spaceMap)
        spaceMap?.scan(url)
    }

    func showPinax(_ section: SidebarSection) {
        if clearSearchSilently() { rebuildItems() }
        folderSizes.cancelAll()
        pathEditing = false
        pinax = section
    }

    private func move(to target: URL, select: String?) {
        if Self.perfLog { navStart = DispatchTime.now().uptimeNanoseconds }
        clearSearchSilently()
        folderSizes.cancelAll()
        quickLookURL = nil
        pendingRename = nil
        pendingSelect = []
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
            listed = listing.items
            listedVersion += 1
            availableBytes = listing.available
            error = nil
            let shown = rebuildItems()
            let hit = pendingSelect.intersection(shown)
            if !hit.isEmpty {
                selection = hit
                pendingSelect = []
                revealToken += 1
            }
            if !inSubfolderSearch { folderSizes.request(items) }
            if listing.sort != prefs.sort { resort() }
            // Sau thao tác file / đổi "hiện file ẩn": Spotlight tự cập nhật, fts và bộ lọc ẩn thì phải tìm lại.
            if inSubfolderSearch, !usingSpotlight || searchShowHidden != prefs.showHidden { startSubfolderSearch(debounce: false) }
        case .failure(let err):
            if err is CancellationError { return }
            guard FileManager.default.fileExists(atPath: folder.path) else {
                recoverFromMissingFolder()
                return
            }
            listed = []
            listedVersion += 1
            availableBytes = nil
            selection = []
            error = Self.classify(err)
            rebuildItems()
        }
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
        let l = listed, r = results, sort = prefs.sort
        let lv = listedVersion, rv = resultsVersion
        sortTask = Task { [weak self] in
            let (sl, sr) = await Task.detached(priority: .userInitiated) { (sort.sorted(l), sort.sorted(r)) }.value
            guard let self, !Task.isCancelled else { return }
            // Danh sách đổi giữa chừng → bản đã sắp là bản cũ, sắp lại.
            guard self.listedVersion == lv, self.resultsVersion == rv else { self.resort(); return }
            self.listed = sl
            self.results = sr
            self.rebuildItems()
        }
    }

    // MARK: Tìm kiếm

    /// Dựng lại `items` từ `listed` / `results` theo trạng thái tìm, bỏ vùng chọn không còn hiện, tăng `generation`.
    /// Trả về tập đường dẫn đang hiện.
    @discardableResult
    private func rebuildItems() -> Set<String> {
        if !isSearching {
            items = listed
        } else if searchScope == .folder {
            let m = searchMatcher
            items = listed.filter { m.matches($0.name) }
        } else {
            items = results
        }
        let shown = Set(items.map { $0.url.path })
        selection.formIntersection(shown)
        generation += 1
        return shown
    }

    private func cancelSearch() {
        searchEpoch += 1
        searchTask?.cancel()
        searchTask = nil
        spotlight?.stop()
        spotlight = nil
        spotlightBuilding = false
        spotlightPending = nil
        spotlightFinished = false
        searchRunning = false
    }

    /// Xoá tìm kiếm khi rời thư mục: không dựng lại `items` (lần nạp sau sẽ làm).
    @discardableResult
    private func clearSearchSilently() -> Bool {
        guard isSearching || !searchText.isEmpty || searchRunning else { return false }
        cancelSearch()
        silentSearchChange = true
        searchText = ""
        silentSearchChange = false
        searchMatcher = NameMatcher("")
        results = []
        resultsVersion += 1
        searchTruncated = false
        return true
    }

    private func searchChanged() {
        let wasSub = inSubfolderSearch
        searchMatcher = NameMatcher(searchText)
        cancelSearch()
        searchTruncated = false
        if !inSubfolderSearch {
            if !results.isEmpty { results = []; resultsVersion += 1 }
            rebuildItems()
            if wasSub { folderSizes.request(items) }
            return
        }
        if !wasSub { folderSizes.cancelAll() }
        // Giữ kết quả cũ trên màn hình tới khi lô đầu của lần tìm mới về (đỡ nháy trống).
        if !wasSub { rebuildItems() }
        startSubfolderSearch(debounce: true)
    }

    /// Ổ khởi động (Spotlight đánh chỉ mục) hay ổ khác (fts).
    private func shouldUseSpotlight(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.path
        if p == home.path || p.hasPrefix(home.path + "/") || p.hasPrefix("/System/Volumes/Data") { return true }
        if let v = try? url.resourceValues(forKeys: [.volumeIsRootFileSystemKey, .volumeURLKey]) {
            if v.volumeIsRootFileSystem == true { return true }
            if let vp = v.volume?.path, vp == "/" || vp == "/System/Volumes/Data" { return true }
        }
        return false
    }

    private func startSubfolderSearch(debounce: Bool) {
        cancelSearch()
        let epoch = searchEpoch
        let root = folder, matcher = searchMatcher, showHidden = prefs.showHidden
        searchRoot = root.path
        searchRootResolved = root.resolvingSymlinksInPath().path
        searchShowHidden = showHidden
        searchRunning = true
        usingSpotlight = shouldUseSpotlight(root) && SpotlightPredicate.make(searchText) != nil
        let query = searchText
        searchTask = Task { [weak self] in
            if debounce { try? await Task.sleep(for: .milliseconds(200)) }
            guard !Task.isCancelled, let self, self.searchEpoch == epoch else { return }
            if self.usingSpotlight, let predicate = SpotlightPredicate.make(query) {
                self.runSpotlight(root: root, predicate: predicate, matcher: matcher, showHidden: showHidden, epoch: epoch)
            } else {
                await self.runFTS(root: root, matcher: matcher, showHidden: showHidden, epoch: epoch)
            }
        }
    }

    private func publishResults(_ items: [FileItem], truncated: Bool) {
        results = items
        resultsVersion += 1
        searchTruncated = truncated
        rebuildItems()
    }

    // Spotlight: URL về từ NSMetadataQuery (main) → lọc, đọc FileItem, sắp ngoài main; gộp các lần giao khi đang bận.

    private func runSpotlight(root: URL, predicate: NSPredicate, matcher: NameMatcher, showHidden: Bool, epoch: Int) {
        let s = SpotlightSearch()
        spotlight = s
        let prefixes = [searchRoot, searchRootResolved]
        s.start(root: root, predicate: predicate) { [weak self] urls, finished in
            guard let self, self.searchEpoch == epoch else { return }
            self.spotlightPending = urls
            if finished { self.spotlightFinished = true }
            self.pumpSpotlight(prefixes: prefixes, matcher: matcher, showHidden: showHidden, epoch: epoch)
        }
    }

    private func pumpSpotlight(prefixes: [String], matcher: NameMatcher, showHidden: Bool, epoch: Int) {
        guard !spotlightBuilding, let urls = spotlightPending else { return }
        spotlightPending = nil
        spotlightBuilding = true
        let sort = prefs.sort
        Task { [weak self] in
            let built = await Task.detached(priority: .userInitiated) {
                Self.buildSpotlightItems(urls, prefixes: prefixes, matcher: matcher, showHidden: showHidden, sort: sort)
            }.value
            guard let self, self.searchEpoch == epoch else { return }
            self.spotlightBuilding = false
            self.publishResults(built.items, truncated: built.truncated)
            if self.spotlightPending != nil {
                self.pumpSpotlight(prefixes: prefixes, matcher: matcher, showHidden: showHidden, epoch: epoch)
            } else if self.spotlightFinished {
                self.searchRunning = false
            }
        }
    }

    private nonisolated static let packageExtensions: Set<String> = [
        "app", "framework", "bundle", "plugin", "appex", "xpc", "kext", "photoslibrary", "rtfd", "xcodeproj", "xcworkspace",
    ]

    private nonisolated static func buildSpotlightItems(_ urls: [URL], prefixes: [String], matcher: NameMatcher,
                                                        showHidden: Bool, sort: FileSort) -> (items: [FileItem], truncated: Bool) {
        var out: [FileItem] = []
        var truncated = false
        for url in urls {
            let path = url.path
            // Phần đường dẫn dưới gốc tìm; gốc chính nó và ngoài gốc đều bỏ.
            guard let prefix = prefixes.first(where: { path.hasPrefix($0 + "/") }) else { continue }
            guard matcher.matches(url.lastPathComponent) else { continue }
            let rel = path.dropFirst(prefix.count + 1).split(separator: "/")
            if !showHidden, rel.contains(where: { $0.hasPrefix(".") }) { continue }
            // Như fts: không đi vào package (chính package vẫn có thể là kết quả).
            if rel.dropLast().contains(where: { packageExtensions.contains(($0 as NSString).pathExtension.lowercased()) }) { continue }
            if out.count >= searchLimit { truncated = true; break }
            if let item = FileItem.make(url: url) { out.append(item) }
        }
        return (sort.sorted(out), truncated)
    }

    // fts: duyệt trong Task.detached, gom FileItem trong task, đẩy về main ≤5 lần/s.

    private final class FTSBox: @unchecked Sendable {
        var items: [FileItem] = []
        var lastPublish: UInt64 = 0
    }

    private func runFTS(root: URL, matcher: NameMatcher, showHidden: Bool, epoch: Int) async {
        let sort = prefs.sort
        let skip: Set<String> = [home.appendingPathComponent("Library/Containers").path,
                                 home.appendingPathComponent("Library/Group Containers").path]
        let options = NameSearch.Options(includeHidden: showHidden, limit: Self.searchLimit, skipPaths: skip)
        let work = Task.detached(priority: .userInitiated) { [weak self] in
            let model = self
            let box = FTSBox()
            do {
                let truncated = try NameSearch(options: options).run(root: root, matcher: matcher) { urls in
                    box.items.append(contentsOf: urls.compactMap { FileItem.make(url: $0) })
                    let now = DispatchTime.now().uptimeNanoseconds
                    guard now - box.lastPublish >= 200_000_000 else { return }
                    box.lastPublish = now
                    let snap = sort.sorted(box.items)
                    Task { @MainActor in
                        guard let model, model.searchEpoch == epoch else { return }
                        model.publishResults(snap, truncated: false)
                    }
                }
                let final = sort.sorted(box.items)
                await MainActor.run {
                    guard let model, model.searchEpoch == epoch else { return }
                    model.publishResults(final, truncated: truncated)
                    model.searchRunning = false
                }
            } catch {
                // Huỷ thì lần tìm mới đã tiếp quản (epoch khác); lỗi khác thì dừng "đang tìm".
                await MainActor.run {
                    guard let model, model.searchEpoch == epoch else { return }
                    model.searchRunning = false
                }
            }
        }
        await withTaskCancellationHandler { _ = await work.value } onCancel: { work.cancel() }
    }

    /// Thư mục cha của kết quả, tương đối so với gốc tìm (cột Where); chính gốc → tên gốc.
    func searchWhere(for item: FileItem) -> String {
        let parent = item.url.deletingLastPathComponent().path
        for root in [searchRoot, searchRootResolved] {
            if parent == root { return FileManager.default.displayName(atPath: searchRoot) }
            if parent.hasPrefix(root + "/") { return String(parent.dropFirst(root.count + 1)) }
        }
        return parent
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
