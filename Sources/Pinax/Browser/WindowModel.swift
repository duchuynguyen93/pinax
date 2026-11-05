import AppKit
import Observation
import PinaxCore

/// Một cửa sổ / tab: một hoặc hai pane (`BrowserModel`), pane nào đang active. Menu, sidebar, toolbar tác động lên pane active.
@MainActor @Observable
final class WindowModel {
    let primary: BrowserModel
    private(set) var secondary: BrowserModel?
    private(set) var activeIsSecondary = false
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored private let make: () -> BrowserModel

    init(make: @escaping () -> BrowserModel) {
        self.make = make
        primary = make()
        wire(primary)
    }

    var isDual: Bool { secondary != nil }
    var active: BrowserModel { activeIsSecondary ? (secondary ?? primary) : primary }
    /// Pane còn lại; nil khi chỉ có một pane.
    var other: BrowserModel? { secondary == nil ? nil : (activeIsSecondary ? primary : secondary) }
    var panes: [BrowserModel] { [primary] + (secondary.map { [$0] } ?? []) }

    func otherPane(of pane: BrowserModel) -> BrowserModel? {
        guard let s = secondary else { return nil }
        return pane === primary ? s : (pane === s ? primary : nil)
    }

    // MARK: Cửa sổ, dual

    func attach(window: NSWindow) {
        let first = self.window !== window
        self.window = window
        for p in panes { p.window = window }
        // Mở sẵn hai khung (workspace, khôi phục) trước khi có cửa sổ → nới cửa sổ một lần khi gắn.
        if first, isDual { DispatchQueue.main.async { [weak self] in self?.widenForDual() } }
    }

    /// Nối pane vào cửa sổ: cửa sổ, cửa sổ-model, callback kích hoạt / chuyển pane.
    private func wire(_ pane: BrowserModel) {
        pane.window = window
        pane.windowModel = self
        pane.onActivate = { [weak self, weak pane] in
            guard let self, let pane else { return }
            activate(pane)
        }
        pane.onSwitchPane = { [weak self] in self?.switchPane() }
    }

    func toggleDual() {
        if isDual { closeDual() } else { openDual(at: active.folder.path) }
    }

    /// Mở pane phải tại `path` (no-op nếu đã dual).
    func openDual(at path: String, activeRight: Bool = false) {
        guard secondary == nil else { return }
        let pane = make()
        wire(pane)
        pane.start(path: path)
        secondary = pane
        activeIsSecondary = activeRight
        widenForDual()
    }

    /// Hai khung cần chỗ: cửa sổ hẹp hơn 1300 pt thì nới ra (trong giới hạn màn hình), giữ mép trái.
    private func widenForDual() {
        guard let w = primary.window, w.frame.width < 1300 else { return }
        var f = w.frame
        let screen = w.screen?.visibleFrame ?? f
        f.size.width = min(1300, screen.width)
        if f.maxX > screen.maxX { f.origin.x = max(screen.minX, screen.maxX - f.width) }
        w.setFrame(f, display: true, animate: w.isVisible)
    }

    /// Đóng pane phải, giữ nguyên pane trái.
    func closeDual() {
        guard let s = secondary else { return }
        s.folderSizes.cancelAll()
        s.quickLookURL = nil
        s.onActivate = nil
        s.onSwitchPane = nil
        activeIsSecondary = false
        secondary = nil
    }

    // MARK: Pane active

    func activate(_ pane: BrowserModel) {
        let toSecondary: Bool
        if pane === secondary { toSecondary = true } else if pane === primary { toSecondary = false } else { return }
        if activeIsSecondary != toSecondary { activeIsSecondary = toSecondary }
    }

    /// Tab: đổi pane active và đưa focus vào bảng / lưới của pane đó.
    func switchPane() {
        guard isDual else { return }
        activeIsSecondary.toggle()
        active.focusContent()
    }

    // MARK: Chép / chuyển sang pane kia

    /// F5 / F6: pane `source` có vùng chọn, pane kia đang xem một thư mục ghi được, và thao tác hợp lệ (như khi thả).
    func canTransfer(from source: BrowserModel, kind: TransferKind) -> Bool {
        guard let dest = otherPane(of: source), source.pinax == nil, !source.selection.isEmpty,
              dest.canCreateFolderHere else { return false }
        let mask: NSDragOperation = kind == .move ? [.move] : [.copy]
        return source.dropKind(sources: source.selectedItems.map(\.url), destination: dest.folder, mask: mask) == kind
    }

    func transfer(from source: BrowserModel, kind: TransferKind) {
        guard canTransfer(from: source, kind: kind), let dest = otherPane(of: source) else { return }
        source.enqueueTransfer(source.selectedItems.map(\.url), kind: kind, to: dest.folder, selectIn: dest)
    }
}
