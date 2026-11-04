import AppKit
import PinaxCore

/// Kích thước + số mục của thư mục, tính nền bằng `SizeCalculator`.
/// Tối đa 2 tác vụ song song, cache chung theo (đường dẫn, mtime), huỷ khi rời thư mục.
@MainActor
final class FolderSizeStore {
    struct Info { var count: Int?; var size: Int64? }
    private final class Box { let info: Info; init(_ i: Info) { info = i } }

    private static let cache: NSCache<NSString, Box> = {
        let c = NSCache<NSString, Box>()
        c.countLimit = 5000
        return c
    }()

    private let maxConcurrent = 2
    private var queue: [FileItem] = []
    private var queued = Set<String>()
    private var running: [String: Task<Info?, Never>] = [:]
    private var epoch = 0
    private var handlers: [ObjectIdentifier: (String) -> Void] = [:]

    private static func key(_ item: FileItem) -> NSString {
        "\(item.url.path)|\(item.modified?.timeIntervalSinceReferenceDate ?? 0)" as NSString
    }

    private static func wants(_ item: FileItem) -> Bool { item.isDirectory && !item.isSymlink && !item.isAlias }

    /// Đã tính xong chưa (nil = chưa, UI hiện "…").
    func info(for item: FileItem) -> Info? { Self.cache.object(forKey: Self.key(item))?.info }

    /// Gọi lại (trên main) mỗi khi một thư mục tính xong; `owner` để gỡ đăng ký.
    func observe(_ owner: AnyObject, _ handler: @escaping (String) -> Void) { handlers[ObjectIdentifier(owner)] = handler }
    func stopObserving(_ owner: AnyObject) { handlers[ObjectIdentifier(owner)] = nil }

    /// Xếp hàng các thư mục chưa có kết quả (bỏ qua mục đã cache / đang xếp / đang chạy).
    func request(_ items: [FileItem]) {
        for item in items where Self.wants(item) {
            let path = item.url.path
            guard info(for: item) == nil, !queued.contains(path), running[path] == nil else { continue }
            queued.insert(path)
            queue.append(item)
        }
        pump()
    }

    /// Rời thư mục: bỏ hàng đợi và huỷ các tác vụ đang chạy.
    func cancelAll() {
        epoch += 1
        queue.removeAll()
        queued.removeAll()
        for t in running.values { t.cancel() }
        running.removeAll()
    }

    private func pump() {
        while running.count < maxConcurrent, !queue.isEmpty {
            start(queue.removeFirst())
        }
    }

    private func start(_ item: FileItem) {
        let path = item.url.path, url = item.url, key = Self.key(item), myEpoch = epoch
        queued.remove(path)
        let work = Task.detached(priority: .utility) { () -> Info? in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
            let count = names.reduce(0) { $0 + ($1.hasPrefix(".") ? 0 : 1) }
            guard let size = try? SizeCalculator.allocatedSize(of: url) else { return nil }
            return Info(count: count, size: size)
        }
        running[path] = work
        Task { [weak self] in
            let result = await work.value
            guard let self, self.epoch == myEpoch else { return }
            self.running[path] = nil
            if let result {
                Self.cache.setObject(Box(result), forKey: key)
                for h in self.handlers.values { h(path) }
            }
            self.pump()
        }
    }
}
