import AppKit
import PinaxCore

/// Clipboard + nhân bản của trình duyệt: mọi thứ đi qua `TransferQueue` → `TransferRunner` (PathGuard, journal, hoàn tác).
extension BrowserModel {
    static let fileURLOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    // MARK: Điều kiện bật / tắt

    var canCopySelection: Bool { pinax == nil && !selection.isEmpty }

    /// Pasteboard có file và thư mục này ghi được.
    var canPaste: Bool {
        guard pinax == nil, canCreateFolderHere else { return false }
        return NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: Self.fileURLOptions)
    }

    /// Cắt = chép + chuyển khi dán, nên mọi mục phải sửa được.
    var canCutSelection: Bool {
        guard canCopySelection else { return false }
        let ops = fileOps
        return selectedItems.allSatisfy { ops.canModify($0.url) }
    }

    var canDuplicateSelection: Bool { canCopySelection && canCreateFolderHere }

    /// Số file trên pasteboard (để đặt tên mục menu).
    var pasteboardFileCount: Int {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: Self.fileURLOptions) as? [URL])?.count ?? 0
    }

    // MARK: Copy / Paste

    /// ⌘C: ghi file đang chọn lên pasteboard để Pinax và Finder dán được.
    func copySelectionToPasteboard() {
        guard canCopySelection else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(selectedItems.map(\.url) as [NSURL])
        ClipboardCut.clear()
    }

    /// ⌘X: như ⌘C nhưng nhớ là "cắt" → ⌘V sau đó chuyển file; mục hiện mờ tới khi dán / pasteboard đổi.
    func cutSelectionToPasteboard() {
        guard canCutSelection else { NSSound.beep(); return }
        let items = selectedItems
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(items.map(\.url) as [NSURL])
        ClipboardCut.mark(paths: Set(items.map(\.url.path)))
    }

    /// ⌘V (chép) / ⌥⌘V (chuyển) vào thư mục đang xem.
    func pasteFromPasteboard(move: Bool) {
        guard canPaste,
              let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: Self.fileURLOptions) as? [URL],
              !urls.isEmpty else { NSSound.beep(); return }
        // Pasteboard vẫn là lần cắt của Pinax → chuyển rồi bỏ trạng thái cắt.
        let wasCut = ClipboardCut.isActive
        enqueueTransfer(urls, kind: move || wasCut ? .move : .copy)
        if wasCut { ClipboardCut.clear() }
    }

    func duplicateSelection() {
        guard canDuplicateSelection else { return }
        enqueueTransfer(selectedItems.map(\.url), kind: .duplicate)
    }

    /// `selectIn`: pane sẽ chọn các mục mới tạo (mặc định chính pane này); dual pane truyền pane đích.
    func enqueueTransfer(_ urls: [URL], kind: TransferKind, to dest: URL? = nil, selectIn target: BrowserModel? = nil) {
        let dest = dest ?? folder
        transfers.enqueue(sources: urls, destination: dest, kind: kind, window: window ?? NSApp.keyWindow) { [weak self, weak target] created in
            (target ?? self)?.selectCreated(created, in: dest)
        }
    }

    /// Job xong vào đúng thư mục đang xem → chọn các mục mới; nếu danh sách chưa có thì chờ lần nạp sau.
    private func selectCreated(_ created: [URL], in dest: URL) {
        guard !created.isEmpty, pinax == nil, folder.standardizedFileURL.path == dest.standardizedFileURL.path else { return }
        let parent = dest.standardizedFileURL.path
        let paths = Set(created.filter { $0.deletingLastPathComponent().standardizedFileURL.path == parent }
            .map { $0.standardizedFileURL.path })
        guard !paths.isEmpty else { return }
        pendingSelect = paths
        reload()
    }

    // MARK: Kéo thả

    /// File URL trên một pasteboard kéo thả.
    static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(forClasses: [NSURL.self], options: fileURLOptions) as? [URL]) ?? []
    }

    /// Kiểu thao tác cho một cú thả (như Finder: ⌥ = chép, ⌘ = chuyển, mặc định theo ổ đĩa). nil = từ chối.
    func dropKind(sources: [URL], destination: URL, mask: NSDragOperation) -> TransferKind? {
        let dest = destination.standardizedFileURL.path
        let paths = sources.map { $0.standardizedFileURL.path }
        guard !sources.isEmpty, fileOps.canCreateFolder(in: destination),
              !paths.allSatisfy({ $0 == dest }) else { return nil }
        // Không thả thư mục vào chính nó / con của nó.
        if paths.contains(where: { dest.hasPrefix($0 + "/") }) { return nil }

        let canCopy = mask.contains(.copy) || mask.contains(.generic)
        let canMove = mask.contains(.move) || mask.contains(.generic)
        var kind: TransferKind
        if mask == [.copy] {
            kind = .copy
        } else if mask == [.move] || (mask.contains(.generic) && !mask.contains(.copy)) {
            kind = .move
        } else {
            kind = TransferPlan.sameVolume(sources[0], destination) ? .move : .copy
        }
        if kind == .move, !sources.allSatisfy({ fileOps.canModify($0) }) { kind = .copy }
        // Nguồn kéo không cho phép kiểu đã chọn thì thử kiểu còn lại.
        if kind == .copy, !canCopy { kind = .move }
        else if kind == .move, !canMove { kind = .copy }
        switch kind {
        case .copy: guard canCopy else { return nil }
        case .move:
            guard canMove, sources.allSatisfy({ fileOps.canModify($0) }) else { return nil }
            // Mọi nguồn đã nằm sẵn trong đích → không có gì để chuyển.
            if sources.allSatisfy({ $0.deletingLastPathComponent().standardizedFileURL.path == dest }) { return nil }
        default: return nil
        }
        return kind
    }

    /// Thả file vào `destination`; xếp hàng qua TransferQueue (hỏi trùng tên, journal, hoàn tác).
    /// Kéo sang Finder/app khác thì Finder tự làm, không qua journal của Pinax.
    func performDrop(sources: [URL], destination: URL, kind: TransferKind) {
        enqueueTransfer(sources, kind: kind, to: destination)
    }
}
