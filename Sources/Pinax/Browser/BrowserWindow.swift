import SwiftUI
import AppKit
import QuickLook
import PinaxCore

/// Hạt giống của một cửa sổ trình duyệt (khoá của `WindowGroup(for:)`). `id` để mỗi lần mở là một cửa sổ riêng.
struct BrowserSeed: Codable, Hashable {
    var id = UUID()
    var path: String?
    var asTab = false
}

extension FocusedValues {
    @Entry var browser: BrowserModel?
}

/// Gốc của một cửa sổ / tab: sở hữu `BrowserModel`, lưu - khôi phục thư mục, cấu hình tab.
struct BrowserRoot: View {
    @Environment(AppEnvironment.self) private var env
    let seed: BrowserSeed
    @State private var model: BrowserModel
    @SceneStorage("pinax.browser.folder") private var storedPath = ""

    init(seed: BrowserSeed, env: AppEnvironment) {
        self.seed = seed
        _model = State(initialValue: BrowserModel(prefs: env.prefs, toast: env.toast))
    }

    var body: some View {
        BrowserWindowView(model: model)
            // Đổi ngôn ngữ → dựng lại cây view; model nằm ở trên `.id` nên không mất trạng thái.
            .id(env.settings.langPref)
            .focusedSceneValue(\.browser, model)
            .background(WindowAccessor { window in
                window.tabbingIdentifier = "pinax.browser"
                window.tabbingMode = .automatic
                if seed.asTab { TabRequest.attach(window) }
            })
            .task { model.start(path: initialPath()) }
            .onChange(of: model.folder) {
                storedPath = model.folder.path
                env.prefs.rememberFolder(model.folder)
            }
            .onChange(of: env.prefs.sort) { model.resort() }
            .onChange(of: env.prefs.showHidden) { model.reload() }
    }

    /// PINAX_OPEN (QA) > thư mục đã lưu của cửa sổ này > thư mục seed (⌘T) > thư mục cuối dùng > Home.
    private func initialPath() -> String {
        if let p = ProcessInfo.processInfo.environment["PINAX_OPEN"], !p.isEmpty { return p }
        if !storedPath.isEmpty { return storedPath }
        if let p = seed.path { return p }
        return env.prefs.lastFolder ?? env.settings.home.path
    }
}

struct BrowserWindowView: View {
    @Bindable var model: BrowserModel

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 260)
        } detail: {
            Group {
                if let section = model.pinax {
                    switch section {
                    case .smartClean: SmartCleanView()
                    case .downloads: TidyView()
                    case .history: HistoryView()
                    }
                } else {
                    BrowserContent(model: model)
                }
            }
            .navigationTitle(model.title)
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
                    Picker(L("View", "Kiểu xem"), selection: $model.viewMode) {
                        Image(systemName: "list.bullet").tag(BrowserViewMode.list)
                            .help(L("As List (⌘1)", "Dạng danh sách (⌘1)"))
                        Image(systemName: "square.grid.2x2").tag(BrowserViewMode.icons)
                            .help(L("As Icons (⌘2)", "Dạng biểu tượng (⌘2)"))
                    }
                    .pickerStyle(.segmented)
                    .disabled(model.pinax != nil)
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
                Button("") { model.viewMode = .list }.keyboardShortcut("1", modifiers: .command)
                Button("") { model.viewMode = .icons }.keyboardShortcut("2", modifiers: .command)
            }
            .opacity(0).allowsHitTesting(false).accessibilityHidden(true)
        }
        .frame(minWidth: 900, minHeight: 560)
        .overlay(alignment: .bottom) { ToastView().padding(.bottom, 40) }
    }
}

/// Path bar + danh sách / lưới icon + status bar.
struct BrowserContent: View {
    @Bindable var model: BrowserModel

    var body: some View {
        VStack(spacing: 0) {
            PathBar(model: model)
            Divider()
            Group {
                switch model.viewMode {
                case .list:
                    FileListView(model: model, generation: model.generation, resetToken: model.resetToken,
                                 revealToken: model.revealToken, sort: model.prefs.sort, pathEditing: model.pathEditing)
                case .icons:
                    IconGridView(model: model, generation: model.generation, resetToken: model.resetToken,
                                 revealToken: model.revealToken, iconSize: model.iconSize, pathEditing: model.pathEditing)
                }
            }
            .overlay { stateOverlay }
            Divider()
            StatusBar(model: model)
        }
        .quickLookPreview($model.quickLookURL, in: model.quickLookURLs)
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
        } else if model.items.isEmpty && !model.isLoading {
            Text(L("This folder is empty", "Thư mục trống"))
                .foregroundStyle(.secondary)
                .allowsHitTesting(false)
        }
    }
}
