import Foundation

/// Theo dõi một thư mục bằng DispatchSource trên fd của nó.
/// - `.changed`: có mục được thêm / xoá / đổi tên trong thư mục (debounce). Sửa nội dung file con thì kernel không báo.
/// - `.vanished`: chính thư mục bị xoá / đổi tên / di chuyển; watcher tự dừng sau đó.
/// Handler chạy trên queue riêng của watcher.
public final class DirectoryWatcher: @unchecked Sendable {
    public enum Event: Sendable, Equatable { case changed, vanished }

    public let url: URL
    private let debounce: TimeInterval
    private let queue = DispatchQueue(label: "pinax.directory-watcher")
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let handler: @Sendable (Event) -> Void

    /// nil nếu không mở được thư mục (không tồn tại / không có quyền).
    public init?(url: URL, debounce: TimeInterval = 0.2, handler: @escaping @Sendable (Event) -> Void) {
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        self.url = url
        self.debounce = debounce
        self.handler = handler

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename], queue: queue)
        src.setEventHandler { [weak self] in self?.handle(src.data) }
        src.setCancelHandler { close(fd) } // fd luôn được đóng đúng một lần, kể cả khi deinit
        source = src
        src.resume()
    }

    deinit { source?.cancel() }

    /// Dừng và đóng fd. Gọi nhiều lần an toàn.
    public func stop() {
        queue.async { [self] in teardown() } // async: an toàn khi gọi từ handler
    }

    private func teardown() {
        pending?.cancel()
        pending = nil
        source?.cancel()
        source = nil
    }

    private func handle(_ flags: DispatchSource.FileSystemEvent) {
        guard source != nil else { return }
        if !flags.isDisjoint(with: [.delete, .rename]) {
            teardown()
            handler(.vanished)
            return
        }
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.source != nil else { return }
            self.handler(.changed)
        }
        pending = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }
}
