import AppKit
import PinaxCore

/// Mục menu giữ closure xử lý (tự làm target).
final class ActionMenuItem: NSMenuItem {
    var handler: (() -> Void)?

    convenience init(_ title: String, key: String = "", mask: NSEvent.ModifierFlags = [], enabled: Bool = true,
                     handler: @escaping () -> Void) {
        self.init(title: title, action: #selector(fire), keyEquivalent: key)
        keyEquivalentModifierMask = mask
        target = self
        isEnabled = enabled
        self.handler = handler
    }

    @objc private func fire() { handler?() }
}

/// Context menu của list / icon view (chuột phải vào mục hoặc chỗ trống).
@MainActor
enum BrowserMenu {
    static func make(model: BrowserModel) -> NSMenu {
        let items = model.selectedItems
        let menu = NSMenu()
        menu.autoenablesItems = false
        let folderTarget = items.count == 1 && items[0].isNavigableFolder ? items[0].url : model.folder

        if !items.isEmpty {
            menu.addItem(ActionMenuItem(L("Open", "Mở")) { model.open(model.selectedItems) })
            let openWith = NSMenuItem(title: L("Open With", "Mở bằng"), action: nil, keyEquivalent: "")
            openWith.submenu = openWithMenu(for: items.map(\.url))
            menu.addItem(openWith)
            menu.addItem(ActionMenuItem(L("Quick Look", "Xem nhanh")) {
                if model.quickLookURL == nil { model.toggleQuickLook() }
            })
            menu.addItem(.separator())
            menu.addItem(ActionMenuItem(L("Rename", "Đổi tên"), enabled: model.canRenameSelection) { model.beginRenameSelection() })
        }
        menu.addItem(ActionMenuItem(L("New Folder", "Thư mục mới"), key: "n", mask: [.command, .shift],
                                    enabled: model.canCreateFolderHere) { model.newFolder() })
        if !items.isEmpty {
            menu.addItem(ActionMenuItem(L("Duplicate", "Nhân bản"), key: "d", mask: .command,
                                        enabled: model.canDuplicateSelection) { model.duplicateSelection() })
            menu.addItem(ActionMenuItem(L("Move to Trash", "Chuyển vào Thùng rác"), key: "\u{8}", mask: .command,
                                        enabled: model.canTrashSelection) { model.trashSelection() })
        }
        if !items.isEmpty, let wm = model.windowModel, wm.isDual {
            menu.addItem(ActionMenuItem(L("Copy to Other Pane", "Chép sang khung kia"), key: fnKey(NSF5FunctionKey),
                                        enabled: wm.canTransfer(from: model, kind: .copy)) {
                wm.transfer(from: model, kind: .copy)
            })
            menu.addItem(ActionMenuItem(L("Move to Other Pane", "Chuyển sang khung kia"), key: fnKey(NSF6FunctionKey),
                                        enabled: wm.canTransfer(from: model, kind: .move)) {
                wm.transfer(from: model, kind: .move)
            })
        }
        menu.addItem(.separator())
        if !items.isEmpty {
            menu.addItem(ActionMenuItem(L("Copy", "Chép"), key: "c", mask: .command,
                                        enabled: model.canCopySelection) { model.copySelectionToPasteboard() })
        }
        let n = model.pasteboardFileCount
        let pasteTitle = n == 0 ? L("Paste", "Dán")
            : n == 1 ? L("Paste Item", "Dán mục") : L("Paste \(n) Items", "Dán \(n) mục")
        menu.addItem(ActionMenuItem(pasteTitle, key: "v", mask: .command, enabled: model.canPaste) {
            model.pasteFromPasteboard(move: false)
        })
        menu.addItem(ActionMenuItem(L("Copy Path", "Chép đường dẫn"), key: "c", mask: [.option, .command]) { model.copyPath() })
        menu.addItem(ActionMenuItem(L("Show in Finder", "Hiện trong Finder")) { model.showInFinder() })
        menu.addItem(ActionMenuItem(L("Analyze Size", "Phân tích dung lượng"), enabled: model.spaceMap != nil) {
            model.analyzeSize(folderTarget)
        })
        menu.addItem(.separator())
        let terminal = ExternalApps.terminal, editor = ExternalApps.editor
        menu.addItem(ActionMenuItem(L("Open in Terminal", "Mở trong Terminal"), enabled: terminal != nil) {
            if let terminal { ExternalApps.open(folderTarget, with: terminal) }
        })
        menu.addItem(ActionMenuItem(L("Open in Editor", "Mở trong Editor"), enabled: editor != nil) {
            if let editor { ExternalApps.open(folderTarget, with: editor) }
        })
        return menu
    }

    private static func fnKey(_ code: Int) -> String { String(UnicodeScalar(code).map(Character.init) ?? " ") }

    /// App mặc định (đánh dấu) trước, rồi các app khác theo tên, cuối cùng "Other…". Lấy danh sách theo mục đầu tiên.
    private static func openWithMenu(for urls: [URL]) -> NSMenu {
        let sub = NSMenu()
        sub.autoenablesItems = false
        let ws = NSWorkspace.shared
        guard let first = urls.first else { return sub }
        let entries = OpenWithOrdering.order(apps: ws.urlsForApplications(toOpen: first),
                                             defaultApp: ws.urlForApplication(toOpen: first)) {
            FileManager.default.displayName(atPath: $0.path)
        }
        for e in entries {
            let title = e.isDefault ? L("\(e.name) (default)", "\(e.name) (mặc định)") : e.name
            let item = ActionMenuItem(title) { open(urls, with: e.url) }
            let icon = ws.icon(forFile: e.url.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            sub.addItem(item)
            if e.isDefault { sub.addItem(.separator()) }
        }
        if !entries.isEmpty { sub.addItem(.separator()) }
        sub.addItem(ActionMenuItem(L("Other…", "Khác…")) { chooseApp(for: urls) })
        return sub
    }

    private static func open(_ urls: [URL], with app: URL) {
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func chooseApp(for urls: [URL]) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = L("Open", "Mở")
        guard panel.runModal() == .OK, let app = panel.url else { return }
        open(urls, with: app)
    }
}
