import AppKit
import PinaxCore

/// Terminal / Editor dùng cho "Open in Terminal / Editor": danh sách app có trên máy + lựa chọn đã lưu.
enum ExternalApps {
    static let terminalKey = "pinax.openIn.terminal"
    static let editorKey = "pinax.openIn.editor"

    static func resolve(_ bundleID: String) -> URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static var terminals: [CatalogApp] { AppCatalog.installedTerminals(resolve: resolve) }
    static var editors: [CatalogApp] { AppCatalog.installedEditors(resolve: resolve) }

    /// App đã chọn nếu còn cài; không thì app đầu tiên có trên máy; không có gì → nil.
    static func chosen(_ list: [CatalogApp], stored: String) -> CatalogApp? {
        list.first { $0.bundleID == stored } ?? list.first
    }

    static var terminal: CatalogApp? {
        chosen(terminals, stored: UserDefaults.standard.string(forKey: terminalKey) ?? "")
    }

    static var editor: CatalogApp? {
        chosen(editors, stored: UserDefaults.standard.string(forKey: editorKey) ?? "")
    }

    static func open(_ folder: URL, with app: CatalogApp) {
        NSWorkspace.shared.open([folder], withApplicationAt: app.url, configuration: NSWorkspace.OpenConfiguration())
    }
}
