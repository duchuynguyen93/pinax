import AppKit
import PinaxCore

/// Trạng thái "cắt" dùng chung cho cả app: ⌘X ghi URL lên pasteboard rồi nhớ lại changeCount.
/// Còn khớp changeCount thì ⌘V = chuyển; pasteboard đổi thì thôi (mục hết mờ khi vẽ lại).
@MainActor
enum ClipboardCut {
    static let didChange = Notification.Name("pinax.clipboardCut.didChange")
    private(set) static var state: CutState?

    /// Gọi ngay sau khi đã ghi pasteboard.
    static func mark(paths: Set<String>) {
        state = CutState(changeCount: NSPasteboard.general.changeCount, paths: paths)
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    static func clear() {
        guard state != nil else { return }
        state = nil
        NotificationCenter.default.post(name: didChange, object: nil)
    }

    /// Pasteboard hiện tại còn là lần cắt của Pinax.
    static var isActive: Bool { state?.isActive(currentChangeCount: NSPasteboard.general.changeCount) ?? false }

    static func isCut(_ path: String) -> Bool {
        state?.isCut(path, currentChangeCount: NSPasteboard.general.changeCount) ?? false
    }

    /// Hệ số alpha khi vẽ một mục (mờ nếu đang bị cắt).
    static func alpha(_ path: String) -> CGFloat { isCut(path) ? 0.5 : 1 }
}
