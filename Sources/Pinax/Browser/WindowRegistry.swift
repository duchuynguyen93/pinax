import AppKit
import PinaxCore

/// NSWindow → WindowModel (yếu hai phía) để chụp trạng thái các tab thành workspace.
@MainActor
final class WindowRegistry {
    static let shared = WindowRegistry()

    private let models = NSMapTable<NSWindow, WindowModel>.weakToWeakObjects()
    private var seeds: [UUID: WeakWindow] = [:]

    private struct WeakWindow { weak var window: NSWindow? }

    func register(_ window: NSWindow, model: WindowModel, seed: UUID) {
        models.setObject(model, forKey: window)
        seeds = seeds.filter { $0.value.window != nil }
        seeds[seed] = WeakWindow(window: window)
    }

    /// Chờ cửa sổ của `seed` đăng ký (sau khi đã gộp tab); nil nếu quá ~2 giây.
    func waitForWindow(seed: UUID) async -> NSWindow? {
        for _ in 0..<40 {
            if let w = seeds[seed]?.window { return w }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    /// Các tab của nhóm chứa `window`, theo thứ tự tab.
    func tabStates(for window: NSWindow) -> [TabState] {
        (window.tabbedWindows ?? [window]).compactMap { models.object(forKey: $0) }.map { win in
            TabState(left: win.primary.folder.path, right: win.secondary?.folder.path,
                     viewMode: win.active.viewMode.rawValue, activeRight: win.activeIsSecondary)
        }
    }
}

/// Hộp thoại nhập tên (NSAlert + ô chữ). Tên rỗng → giữ `initial`.
@MainActor
enum NamePrompt {
    static func ask(title: String, message: String, initial: String, confirm: String,
                    window: NSWindow?, done: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: L("Cancel", "Huỷ"))
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            done(name.isEmpty ? initial : name)
        }
        if let window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
    }
}

extension WorkspacesModel {
    /// ⌃⌘S: lưu các tab của cửa sổ thành workspace mới.
    func saveWindow(_ window: NSWindow?) {
        guard let window else { return }
        let tabs = WindowRegistry.shared.tabStates(for: window)
        guard let first = tabs.first else { return }
        NamePrompt.ask(title: L("Save Window as Workspace", "Lưu cửa sổ thành workspace"),
                       message: L("Name this workspace.", "Đặt tên cho workspace."),
                       initial: FileManager.default.displayName(atPath: first.left),
                       confirm: L("Save", "Lưu"), window: window) { [self] name in
            add(name: name, tabs: tabs)
        }
    }
}
