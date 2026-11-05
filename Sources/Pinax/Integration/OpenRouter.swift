import SwiftUI
import AppKit
import PinaxCore

/// Một cửa ngõ duy nhất cho mọi lối vào từ ngoài (Open With, `open -a`, `pinax://`, Services, phím tắt).
@MainActor
final class OpenRouter {
    static let shared = OpenRouter()

    var env: AppEnvironment?
    private var openWindow: ((BrowserSeed) -> Void)?
    private var pending: [BrowserSeed] = []

    /// Mở `url`: thư mục → cửa sổ (hoặc tab) tại đó; file → thư mục chứa + chọn file; không tồn tại → Home kèm thông báo.
    func open(url: URL, newTab: Bool) {
        let fm = FileManager.default
        let target: String
        if fm.fileExists(atPath: url.path) {
            target = url.path
        } else {
            target = fm.homeDirectoryForCurrentUser.path
            let name = url.path
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(600))
                self?.env?.toast.show(L("Can't find \(name). Showing Home instead.",
                                        "Không tìm thấy \(name). Đang hiện Home."))
            }
        }
        let asTab = newTab && NSApp.keyWindow != nil
        if asTab { TabRequest.prepare() }
        send(BrowserSeed(path: target, asTab: asTab))
    }

    /// Mở workspace: tab đầu là cửa sổ mới, các tab sau gộp vào đó lần lượt (đợi mỗi tab gắn xong rồi mới mở tab kế).
    func openWorkspace(_ ws: Workspace) {
        guard !ws.tabs.isEmpty else { return }
        Task { @MainActor in
            var host: NSWindow?
            for (i, t) in ws.tabs.enumerated() {
                let asTab = i > 0 && host != nil
                if asTab { TabRequest.prepare(host: host) }
                let seed = BrowserSeed(path: t.left, asTab: asTab, secondPath: t.right,
                                       activeRight: t.activeRight, viewMode: t.viewMode)
                send(seed)
                let w = await WindowRegistry.shared.waitForWindow(seed: seed.id)
                if i == 0 { host = w }
            }
        }
    }

    /// Đưa Pinax lên trước; chưa có cửa sổ nào thì mở một cửa sổ mới ở thư mục dùng gần nhất.
    func showOrCreateWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let windows = NSApp.windows.filter { $0.tabbingIdentifier == "pinax.browser" }
        if let w = windows.first(where: { $0.isVisible }) ?? windows.first {
            if w.isMiniaturized { w.deminiaturize(nil) }
            w.makeKeyAndOrderFront(nil)
        } else {
            send(BrowserSeed())
        }
    }

    /// `openWindow` chỉ lấy được từ môi trường SwiftUI; gắn vào một lần rồi xả hàng đợi.
    func connect(env: AppEnvironment, openWindow action: OpenWindowAction) {
        self.env = env
        guard openWindow == nil else { return }
        openWindow = { action(value: $0) }
        let queued = pending
        pending = []
        for seed in queued { openWindow?(seed) }
    }

    private func send(_ seed: BrowserSeed) {
        NSApp.activate(ignoringOtherApps: true)
        if let openWindow { openWindow(seed) } else { pending.append(seed) }
    }

    /// `pinax://open?path=<percent-encoded>`; trả nil nếu không phải URL của Pinax.
    static func path(fromPinaxURL url: URL) -> String? {
        guard url.scheme == "pinax", url.host == "open",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let path = comps.queryItems?.first(where: { $0.name == "path" })?.value, !path.isEmpty
        else { return nil }
        return (path as NSString).expandingTildeInPath
    }

    /// `pinax://workspace?name=<tên>` (không phân biệt hoa/thường); trả nil nếu không phải URL workspace.
    static func workspaceName(fromPinaxURL url: URL) -> String? {
        guard url.scheme == "pinax", url.host == "workspace",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let name = comps.queryItems?.first(where: { $0.name == "name" })?.value, !name.isEmpty
        else { return nil }
        return name
    }

    /// Mở workspace theo tên; không có thì báo bằng toast.
    func openWorkspace(named name: String) {
        guard let env else { return }
        if let ws = env.workspaces.items.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            openWorkspace(ws)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            env.toast.show(L("No workspace named “\(name)”", "Không có workspace tên “\(name)”"))
        }
    }
}

final class PinaxAppDelegate: NSObject, NSApplicationDelegate {
    /// PINAX_OPEN (QA) thì không khôi phục cửa sổ cũ, nếu không mọi cửa sổ khôi phục đều đọc PINAX_OPEN và thành các tab giống hệt nhau.
    /// Chỉ đặt ở miền đăng ký (không ghi ra plist); mở thường vẫn khôi phục đúng các cửa sổ lần trước.
    static func skipWindowRestoration() {
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = ServicesProvider.shared
        NSUpdateDynamicServices()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyModel.shared.start()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for (i, url) in urls.enumerated() {
                if let name = OpenRouter.workspaceName(fromPinaxURL: url) {
                    OpenRouter.shared.openWorkspace(named: name)
                    continue
                }
                let target: URL? = url.isFileURL ? url
                    : OpenRouter.path(fromPinaxURL: url).map { URL(fileURLWithPath: $0) }
                guard let target else { continue }
                OpenRouter.shared.open(url: target, newTab: i > 0)
            }
        }
    }
}

/// Dịch vụ "Open in Pinax" (Finder ▸ chuột phải ▸ Services).
final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()

    @objc func openInPinax(_ pboard: NSPasteboard, userData: String,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let urls = (pboard.readObjects(forClasses: [NSURL.self],
                                       options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else {
            error.pointee = "No folder or file was provided." as NSString
            return
        }
        Task { @MainActor in
            for (i, url) in urls.enumerated() { OpenRouter.shared.open(url: url, newTab: i > 0) }
        }
    }
}
