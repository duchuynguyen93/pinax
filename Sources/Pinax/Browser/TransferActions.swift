import AppKit
import PinaxCore

/// Clipboard + nhân bản của trình duyệt: mọi thứ đi qua `TransferQueue` → `TransferRunner` (PathGuard, journal, hoàn tác).
extension BrowserModel {
    private static let fileURLOptions: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]

    // MARK: Điều kiện bật / tắt

    var canCopySelection: Bool { pinax == nil && !selection.isEmpty }

    /// Pasteboard có file và thư mục này ghi được.
    var canPaste: Bool {
        guard pinax == nil, canCreateFolderHere else { return false }
        return NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: Self.fileURLOptions)
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
    }

    /// ⌘V (chép) / ⌥⌘V (chuyển) vào thư mục đang xem.
    func pasteFromPasteboard(move: Bool) {
        guard canPaste,
              let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: Self.fileURLOptions) as? [URL],
              !urls.isEmpty else { NSSound.beep(); return }
        enqueueTransfer(urls, kind: move ? .move : .copy)
    }

    func duplicateSelection() {
        guard canDuplicateSelection else { return }
        enqueueTransfer(selectedItems.map(\.url), kind: .duplicate)
    }

    private func enqueueTransfer(_ urls: [URL], kind: TransferKind) {
        let dest = folder
        transfers.enqueue(sources: urls, destination: dest, kind: kind, window: window ?? NSApp.keyWindow) { [weak self] created in
            self?.selectCreated(created, in: dest)
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
}
