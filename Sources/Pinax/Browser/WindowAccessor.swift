import SwiftUI
import AppKit

/// Nhận NSWindow chứa view (để cấu hình tab của cửa sổ).
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let v = Probe()
        v.onWindow = onWindow
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        var onWindow: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            DispatchQueue.main.async { [onWindow] in onWindow?(window) }
        }
    }
}

/// ⌘T: cửa sổ mới cần gộp vào nhóm tab của cửa sổ đang mở.
@MainActor
enum TabRequest {
    private static weak var source: NSWindow?

    static func prepare() { source = NSApp.keyWindow }

    /// Gộp `window` làm tab mới của cửa sổ đã ghi nhận (một lần).
    static func attach(_ window: NSWindow) {
        guard let host = source, host !== window else { return }
        source = nil
        host.addTabbedWindow(window, ordered: .above)
        window.makeKeyAndOrderFront(nil)
    }
}
