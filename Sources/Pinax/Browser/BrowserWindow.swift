import SwiftUI
import AppKit
import QuickLook
import PinaxCore

/// Hạt giống của một cửa sổ trình duyệt (khoá của `WindowGroup(for:)`). `id` để mỗi lần mở là một cửa sổ riêng.
struct BrowserSeed: Codable, Hashable {
    var id = UUID()
    var path: String?
    var asTab = false
    /// Khác nil → mở ở chế độ dual pane, pane phải ở thư mục này.
    var secondPath: String?
    /// Dual: pane phải là pane active lúc mở.
    var activeRight = false
    /// Kiểu xem áp lên pane lúc mở (workspace); nil = giữ kiểu hiện tại.
    var viewMode: String?

    init(id: UUID = UUID(), path: String? = nil, asTab: Bool = false, secondPath: String? = nil, activeRight: Bool = false,
         viewMode: String? = nil) {
        self.id = id
        self.path = path
        self.asTab = asTab
        self.secondPath = secondPath
        self.activeRight = activeRight
        self.viewMode = viewMode
    }

    // Trạng thái cửa sổ đã lưu từ bản cũ không có hai khoá mới.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        path = try c.decodeIfPresent(String.self, forKey: .path)
        asTab = try c.decodeIfPresent(Bool.self, forKey: .asTab) ?? false
        secondPath = try c.decodeIfPresent(String.self, forKey: .secondPath)
        activeRight = try c.decodeIfPresent(Bool.self, forKey: .activeRight) ?? false
        viewMode = try c.decodeIfPresent(String.self, forKey: .viewMode)
    }
}

extension FocusedValues {
    @Entry var browser: BrowserModel?
    @Entry var browserWindow: WindowModel?
}

/// Gốc của một cửa sổ / tab: sở hữu `WindowModel` (1-2 pane), lưu - khôi phục thư mục, cấu hình tab.
struct BrowserRoot: View {
    @Environment(AppEnvironment.self) private var env
    let seed: BrowserSeed
    @State private var win: WindowModel
    @SceneStorage("pinax.browser.folder") private var storedPath = ""
    @SceneStorage("pinax.browser.folder2") private var storedPath2 = ""
    @SceneStorage("pinax.browser.activeRight") private var storedActiveRight = false

    init(seed: BrowserSeed, env: AppEnvironment) {
        self.seed = seed
        _win = State(initialValue: WindowModel {
            let m = BrowserModel(prefs: env.prefs, toast: env.toast, history: env.history, transfers: env.transfers, home: env.settings.home)
            m.spaceMap = env.spaceMap
            return m
        })
    }

    var body: some View {
        BrowserWindowView(window: win)
            // Đổi ngôn ngữ → dựng lại cây view; model nằm ở trên `.id` nên không mất trạng thái.
            .id(env.settings.langPref)
            .focusedSceneValue(\.browser, win.active)
            .focusedSceneValue(\.browserWindow, win)
            .background(WindowAccessor { window in
                win.attach(window: window)
                window.tabbingIdentifier = "pinax.browser"
                window.tabbingMode = .automatic
                if seed.asTab { TabRequest.attach(window) }
                WindowRegistry.shared.register(window, model: win, seed: seed.id)
            })
            .task {
                win.primary.start(path: initialPath())
                if let (second, right) = initialSecond() { win.openDual(at: second, activeRight: right) }
                if storedPath.isEmpty || seed.path != nil, let raw = seed.viewMode, let mode = BrowserViewMode(rawValue: raw) {
                    win.panes.forEach { $0.applyPresetViewMode(mode) }
                }
                if let s = Self.takeQASection() { win.primary.showPinax(s) }
                if let dir = Self.takeQASpaceMap() {
                    win.primary.showPinax(.spaceMap)
                    env.spaceMap.scan(URL(fileURLWithPath: dir, isDirectory: true))
                }
                await runQASearch()
                await runQABatchRename()
                await runQATransfer()
            }
            .onChange(of: win.primary.folder) { remember(win.primary) }
            .onChange(of: win.secondary?.folder.path ?? "") {
                storedPath2 = win.secondary?.folder.path ?? ""
                if let s = win.secondary { env.prefs.rememberFolder(s.folder) }
            }
            .onChange(of: win.activeIsSecondary) { storedActiveRight = win.activeIsSecondary }
            .onChange(of: env.prefs.sort) { win.panes.forEach { $0.resort() } }
            .onChange(of: env.prefs.showHidden) { win.panes.forEach { $0.reload() } }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
                if let w = note.object as? NSWindow, w === win.window { win.panes.forEach { $0.git.refresh($0.folder) } }
            }
    }

    private func remember(_ pane: BrowserModel) {
        if pane === win.primary { storedPath = pane.folder.path }
        env.prefs.rememberFolder(pane.folder)
    }

    /// PINAX_OPEN (QA, chỉ cửa sổ đầu tiên) > thư mục đã lưu của cửa sổ này > thư mục seed (⌘T) > thư mục cuối dùng > Home.
    private func initialPath() -> String {
        if let p = Self.takeQAOpenPath() { return p }
        if !storedPath.isEmpty { return storedPath }
        if let p = seed.path { return p }
        return env.prefs.lastFolder ?? env.settings.home.path
    }

    /// Pane phải lúc mở: PINAX_QA_DUAL (QA, cửa sổ đầu) > pane phải đã lưu > seed. nil = đơn.
    private func initialSecond() -> (String, Bool)? {
        if let p = Self.takeQADualPath() { return (p, false) }
        if !storedPath2.isEmpty { return (storedPath2, storedActiveRight) }
        if let p = seed.secondPath, !p.isEmpty { return (p, seed.activeRight) }
        return nil
    }

    /// PINAX_QA_TRANSFER=<nguồn>:<thư mục đích> (QA): chép nguồn vào đích một lần, khi cửa sổ đầu tiên đã mở.
    private func runQATransfer() async {
        guard let (src, dest) = Self.takeQATransfer() else { return }
        try? await Task.sleep(for: .seconds(1))
        env.transfers.enqueue(sources: [URL(fileURLWithPath: src)], destination: URL(fileURLWithPath: dest, isDirectory: true),
                              kind: .copy, window: win.primary.window)
    }

    /// PINAX_QA_SEARCH=<folder|subfolders>:<câu tìm> (QA, chỉ cửa sổ đầu): đặt sẵn tìm kiếm sau khi thư mục nạp xong.
    private func runQASearch() async {
        guard let (scope, query) = Self.takeQASearch() else { return }
        for _ in 0..<100 where win.primary.isLoading { try? await Task.sleep(for: .milliseconds(50)) }
        win.primary.searchScope = scope
        win.primary.searchText = query
    }

    /// PINAX_QA_BATCH_RENAME=1|format|replace|add|case (QA, chỉ cửa sổ đầu): sau khi nạp xong, chọn mọi mục và mở sheet ở kiểu đó với giá trị mẫu.
    private func runQABatchRename() async {
        guard Self.takeQABatchRename() else { return }
        for _ in 0..<100 where win.primary.isLoading { try? await Task.sleep(for: .milliseconds(50)) }
        let m = win.primary
        m.selection = Set(m.items.map(\.url.path))
        m.batchRenameQAPreset = Self.qaBatchRenameMode
        m.beginBatchRename()
    }

    @MainActor private static var qaBatchRenameConsumed = false
    @MainActor private static var qaBatchRenameMode = "format"
    @MainActor private static func takeQABatchRename() -> Bool {
        guard !qaBatchRenameConsumed, let v = ProcessInfo.processInfo.environment["PINAX_QA_BATCH_RENAME"], !v.isEmpty else { return false }
        qaBatchRenameConsumed = true
        qaBatchRenameMode = v == "1" ? "format" : v
        return true
    }

    @MainActor private static var qaSearchConsumed = false
    @MainActor private static func takeQASearch() -> (SearchScope, String)? {
        guard !qaSearchConsumed, let v = ProcessInfo.processInfo.environment["PINAX_QA_SEARCH"], !v.isEmpty else { return nil }
        qaSearchConsumed = true
        guard let colon = v.firstIndex(of: ":"), let scope = SearchScope(rawValue: String(v[..<colon])) else { return nil }
        let query = String(v[v.index(after: colon)...])
        return query.isEmpty ? nil : (scope, query)
    }

    @MainActor private static var qaSectionConsumed = false
    /// PINAX_QA_SECTION=uninstall|smartClean|downloads|spaceMap|history (QA, chỉ cửa sổ đầu): mở thẳng một mục Pinax.
    @MainActor private static func takeQASection() -> SidebarSection? {
        guard !qaSectionConsumed, let v = ProcessInfo.processInfo.environment["PINAX_QA_SECTION"], !v.isEmpty else { return nil }
        qaSectionConsumed = true
        return SidebarSection(rawValue: v)
    }

    @MainActor private static var qaSpaceMapConsumed = false
    /// PINAX_QA_SPACEMAP=<thư mục> (QA, chỉ cửa sổ đầu): mở Space Map và quét thư mục đó.
    @MainActor private static func takeQASpaceMap() -> String? {
        guard !qaSpaceMapConsumed, let v = ProcessInfo.processInfo.environment["PINAX_QA_SPACEMAP"], !v.isEmpty else { return nil }
        qaSpaceMapConsumed = true
        return v
    }

    @MainActor private static var qaTransferConsumed = false
    @MainActor private static func takeQATransfer() -> (String, String)? {
        guard !qaTransferConsumed, let v = ProcessInfo.processInfo.environment["PINAX_QA_TRANSFER"] else { return nil }
        qaTransferConsumed = true
        let parts = v.components(separatedBy: ":")
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return nil }
        return (parts[0], parts[1])
    }

    @MainActor private static var qaOpenConsumed = false
    /// Trả PINAX_OPEN đúng một lần; các cửa sổ mở sau (pinax://, ⌘N) đi theo seed như bình thường.
    @MainActor private static func takeQAOpenPath() -> String? {
        guard !qaOpenConsumed, let p = ProcessInfo.processInfo.environment["PINAX_OPEN"], !p.isEmpty else { return nil }
        qaOpenConsumed = true
        return p
    }

    @MainActor private static var qaDualConsumed = false
    /// PINAX_QA_DUAL=<thư mục>: đúng một lần, cửa sổ đầu tiên mở dual với pane phải ở đó.
    @MainActor private static func takeQADualPath() -> String? {
        guard !qaDualConsumed, let p = ProcessInfo.processInfo.environment["PINAX_QA_DUAL"], !p.isEmpty else { return nil }
        qaDualConsumed = true
        return p
    }
}

struct BrowserWindowView: View {
    @Environment(AppEnvironment.self) private var env
    let window: WindowModel
    @FocusState private var searchFocused: Bool

    private var model: BrowserModel { window.active }

    /// Ô tìm gắn vào pane active; ở màn Pinax thì không có gì để tìm.
    private var searchBinding: Binding<String> {
        window.active.pinax != nil ? .constant("")
            : Binding(get: { window.active.searchText }, set: { window.active.searchText = $0 })
    }

    private var scopeBinding: Binding<SearchScope> {
        Binding(get: { window.active.searchScope }, set: { window.active.searchScope = $0 })
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            VStack(spacing: 0) {
                Group {
                    if let section = model.pinax {
                        switch section {
                        case .smartClean: SmartCleanView()
                        case .downloads: TidyView()
                        case .uninstall: UninstallView()
                        case .spaceMap: SpaceMapView(browser: model)
                        case .history: HistoryView()
                        }
                    } else if let second = window.secondary {
                        HSplitView {
                            BrowserContent(model: window.primary, dual: true).frame(minWidth: 320)
                            BrowserContent(model: second, dual: true).frame(minWidth: 320)
                        }
                    } else {
                        BrowserContent(model: window.primary)
                    }
                }
                TransferStrip()
            }
            .navigationTitle(model.title)
            .searchable(text: searchBinding, placement: .toolbar, prompt: L("Search", "Tìm"))
            .searchScopes(scopeBinding, activation: .onSearchPresentation) {
                ForEach(SearchScope.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .searchFocused($searchFocused)
            .inspector(isPresented: Binding(
                get: { env.prefs.showPreview && model.pinax == nil },
                set: { env.prefs.showPreview = $0 })) {
                PreviewPane(model: model)
                    .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
            }
            .onChange(of: window.searchFocusToken) { if model.pinax == nil { searchFocused = true } }
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { model.back() } label: { Image(systemName: "chevron.left") }
                        .disabled(!model.canGoBack)
                        .help(L("Back", "Quay lại"))
                    Button { model.forward() } label: { Image(systemName: "chevron.right") }
                        .disabled(!model.canGoForward)
                        .help(L("Forward", "Tiến tới"))
                }
                ToolbarItem(placement: .navigation) {
                    Button { model.up() } label: { Image(systemName: "chevron.up") }
                        .disabled(!model.canGoUp)
                        .help(L("Enclosing Folder", "Thư mục cha"))
                }
                ToolbarItem(placement: .primaryAction) {
                    Picker(L("View", "Kiểu xem"), selection: Binding(
                        get: { window.active.viewMode }, set: { window.active.viewMode = $0 })) {
                        Image(systemName: "list.bullet").tag(BrowserViewMode.list)
                            .help(L("As List (⌘1)", "Dạng danh sách (⌘1)"))
                        Image(systemName: "square.grid.2x2").tag(BrowserViewMode.icons)
                            .help(L("As Icons (⌘2)", "Dạng biểu tượng (⌘2)"))
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.pinax != nil)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { env.prefs.showPreview.toggle() } label: { Image(systemName: "sidebar.right") }
                        .disabled(model.pinax != nil)
                        .help(L("Show/Hide Preview (⇧⌘P)", "Hiện/ẩn xem trước (⇧⌘P)"))
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { model.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                        .keyboardShortcut("-", modifiers: .command)
                        .disabled(model.viewMode != .icons || model.iconSize.smaller == nil || model.pinax != nil)
                        .help(L("Smaller Icons (⌘−)", "Biểu tượng nhỏ hơn (⌘−)"))
                    Button { model.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                        .keyboardShortcut("=", modifiers: .command)
                        .disabled(model.viewMode != .icons || model.iconSize.larger == nil || model.pinax != nil)
                        .help(L("Larger Icons (⌘+)", "Biểu tượng lớn hơn (⌘+)"))
                }
            }
        }
        .background {
            // Phím tắt đổi kiểu xem (segmented control không gắn được phím cho từng đoạn).
            Group {
                Button("") { window.active.viewMode = .list }.keyboardShortcut("1", modifiers: .command)
                Button("") { window.active.viewMode = .icons }.keyboardShortcut("2", modifiers: .command)
            }
            .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .frame(minWidth: window.isDual ? 1100 : 900, minHeight: 560)
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 40) }
    }
}

/// Path bar + danh sách / lưới icon + status bar. `dual`: nằm trong dual pane (có vạch / làm mờ theo pane active).
struct BrowserContent: View {
    @Bindable var model: BrowserModel
    var dual = false

    private var isActive: Bool { !dual || model.isActivePane }

    var body: some View {
        VStack(spacing: 0) {
            PathBar(model: model, dual: dual, isActive: isActive)
            Divider()
            Group {
                switch model.viewMode {
                case .list:
                    FileListView(model: model, generation: model.generation, resetToken: model.resetToken,
                                 revealToken: model.revealToken, sort: model.prefs.sort, pathEditing: model.pathEditing,
                                 renameToken: model.renameToken, showWhere: model.inSubfolderSearch)
                case .icons:
                    IconGridView(model: model, generation: model.generation, resetToken: model.resetToken,
                                 revealToken: model.revealToken, iconSize: model.iconSize, pathEditing: model.pathEditing,
                                 renameToken: model.renameToken)
                }
            }
            .overlay { stateOverlay }
            Divider()
            StatusBar(model: model, dimmed: !isActive)
        }
        .quickLookPreview($model.quickLookURL, in: model.quickLookURLs)
        .sheet(isPresented: Binding(get: { model.batchRenameItems != nil },
                                    set: { if !$0 { model.batchRenameItems = nil; model.batchRenameQAPreset = nil } })) {
            if let urls = model.batchRenameItems {
                BatchRenameSheet(urls: urls, qaPreset: model.batchRenameQAPreset,
                                 onApply: { model.applyBatchRename(entries: $0) },
                                 onCancel: { model.batchRenameItems = nil; model.batchRenameQAPreset = nil })
            }
        }
        // Bấm bất kỳ đâu trong pane (kể cả path bar, status bar) → pane active; không chặn click của con.
        .simultaneousGesture(TapGesture().onEnded { model.onActivate?() }, including: dual ? .all : .subviews)
    }

    @ViewBuilder private var stateOverlay: some View {
        if let error = model.error {
            Group {
                switch error {
                case .denied:
                    ContentUnavailableView {
                        Label(L("Access denied", "Không có quyền truy cập"), systemImage: "lock.fill")
                    } description: {
                        Text(L("macOS didn't let Pinax open this folder. Allow access in Privacy & Security, then come back.",
                               "macOS không cho Pinax mở thư mục này. Hãy cấp quyền trong Quyền riêng tư & Bảo mật rồi quay lại."))
                    } actions: {
                        Button(L("Open Privacy & Security", "Mở Quyền riêng tư & Bảo mật")) {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        Button(L("Try Again", "Thử lại")) { model.reload() }
                    }
                case .failed(let message):
                    ContentUnavailableView {
                        Label(L("Can't open this folder", "Không mở được thư mục này"), systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button(L("Try Again", "Thử lại")) { model.reload() }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.background)
        } else if let tag = model.tagName {
            if model.items.isEmpty && !model.isLoading && !model.searchRunning {
                ContentUnavailableView(L("No items tagged “\(tag)”", "Không có mục nào gắn tag “\(tag)”"),
                                       systemImage: "tag",
                                       description: Text(L("Right-click files and choose Tags to add one.",
                                                           "Chuột phải vào file, chọn Tags để gắn.")))
                    .allowsHitTesting(false)
            }
        } else if model.isSearching {
            if model.items.isEmpty && !model.isLoading && !model.searchRunning {
                ContentUnavailableView.search(text: model.searchText)
                    .allowsHitTesting(false)
            }
        } else if model.items.isEmpty && !model.isLoading {
            Text(L("This folder is empty", "Thư mục trống"))
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
        }
    }
}
