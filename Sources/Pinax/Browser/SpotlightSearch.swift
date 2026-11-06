import Foundation

/// Tìm theo tên bằng Spotlight (`NSMetadataQuery`) trong một thư mục. Chạy trên main; chỉ đọc.
/// Báo về toàn bộ kết quả hiện có (≤5 lần/s), `finished` = đã gom xong lần đầu. Sau đó vẫn cập nhật khi file đổi tên / chuyển đi.
@MainActor
final class SpotlightSearch {
    /// Đọc tối đa chừng này kết quả mỗi lần (lọc ẩn / `NameMatcher` còn cắt thêm ở ngoài main).
    static let readLimit = 20_000
    private static let minInterval: TimeInterval = 0.2

    private let query = NSMetadataQuery()
    private var observers: [NSObjectProtocol] = []
    private var lastDelivery = Date.distantPast
    private var delayed: Task<Void, Never>?
    private var gathered = false
    private var handler: (([URL], _ finished: Bool) -> Void)?

    func start(root: URL, predicate: NSPredicate, handler: @escaping ([URL], _ finished: Bool) -> Void) {
        stop()
        self.handler = handler
        gathered = false
        lastDelivery = .distantPast
        query.searchScopes = [root]
        query.predicate = predicate
        let center = NotificationCenter.default
        for name in [Notification.Name.NSMetadataQueryGatheringProgress, .NSMetadataQueryDidUpdate] {
            observers.append(center.addObserver(forName: name, object: query, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.throttledDeliver() }
            })
        }
        observers.append(center.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.gathered = true
                self.deliver()
                self.query.enableUpdates()
            }
        })
        query.start()
    }

    func stop() {
        delayed?.cancel()
        delayed = nil
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        query.stop()
        handler = nil
    }

    isolated deinit { stop() }

    private func throttledDeliver() {
        let wait = Self.minInterval - Date().timeIntervalSince(lastDelivery)
        if wait <= 0 { deliver(); return }
        guard delayed == nil else { return }
        delayed = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, let self else { return }
            delayed = nil
            deliver()
        }
    }

    private func deliver() {
        delayed?.cancel()
        delayed = nil
        lastDelivery = Date()
        query.disableUpdates()
        let n = min(query.resultCount, Self.readLimit)
        var urls: [URL] = []
        urls.reserveCapacity(n)
        for i in 0..<n {
            if let item = query.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                urls.append(URL(fileURLWithPath: path))
            }
        }
        query.enableUpdates()
        handler?(urls, gathered)
    }
}
