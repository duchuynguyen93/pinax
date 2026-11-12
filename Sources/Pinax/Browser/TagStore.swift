import AppKit
import PinaxCore

/// Tag màu của các mục đang hiện, nạp lười theo dòng / ô nhìn thấy (đọc `.tagNamesKey` lúc liệt kê tốn ~+180 ms / 10k file).
/// Request gộp trong một nhịp ngắn rồi đọc một lượt ở nền; `invalidate()` chỉ đánh dấu cũ (vẫn hiện giá trị cũ, đọc lại
/// khi dòng / ô được dựng lại) nên không nháy chấm khi nạp lại thư mục.
@MainActor
final class TagStore {
    private struct Entry { var tags: [String]; var epoch: Int }

    private var cache: [String: Entry] = [:]
    private var epoch = 0
    private var pending: [String] = []
    private var pendingSet = Set<String>()
    private var inFlight = Set<String>()
    private var flushScheduled = false
    private var handlers: [ObjectIdentifier: (String) -> Void] = [:]

    /// Tag đã nạp (có thể là bản cũ); nil = chưa nạp lần nào.
    func tags(for path: String) -> [String]? { cache[path]?.tags }

    /// Gọi lại (trên main) khi tag của một đường dẫn đổi so với bản đã có (hoặc nạp lần đầu ra danh sách khác rỗng).
    func observe(_ owner: AnyObject, _ handler: @escaping (String) -> Void) { handlers[ObjectIdentifier(owner)] = handler }
    func stopObserving(_ owner: AnyObject) { handlers[ObjectIdentifier(owner)] = nil }

    /// Xếp hàng các đường dẫn chưa nạp hoặc đã cũ (bỏ qua mục đang xếp / đang đọc). Rẻ: chỉ tra dict và thêm vào hàng đợi.
    func request(_ paths: [String]) {
        for path in paths {
            if let e = cache[path], e.epoch == epoch { continue }
            guard !pendingSet.contains(path), !inFlight.contains(path) else { continue }
            pendingSet.insert(path)
            pending.append(path)
        }
        scheduleFlush()
    }

    /// Đánh dấu mọi mục là cũ (thư mục nạp lại): lần dựng ô kế tiếp sẽ đọc lại.
    func invalidate() { epoch += 1 }

    /// Các mục vừa đổi tag: đọc lại ngay (giá trị cũ vẫn hiện tới khi có kết quả).
    func forget(_ paths: [String]) {
        for p in paths { cache[p]?.epoch = -1 }
        request(paths)
    }

    private func scheduleFlush() {
        guard !pending.isEmpty, !flushScheduled else { return }
        flushScheduled = true
        Task { [weak self] in
            // Gộp mọi request của một nhịp cuộn / dựng bảng.
            try? await Task.sleep(for: .milliseconds(40))
            self?.flush()
        }
    }

    private func flush() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        let batch = pending, myEpoch = epoch
        pending.removeAll()
        pendingSet.removeAll()
        inFlight.formUnion(batch)
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) { () -> [(String, [String])] in
                batch.map { ($0, TagSupport.tags(of: URL(fileURLWithPath: $0))) }
            }.value
            self?.apply(result, epoch: myEpoch)
        }
    }

    private func apply(_ result: [(String, [String])], epoch loaded: Int) {
        var again: [String] = []
        for (path, tags) in result {
            inFlight.remove(path)
            let old = cache[path]?.tags
            cache[path] = Entry(tags: tags, epoch: loaded)
            if loaded != epoch { again.append(path) }
            if tags != (old ?? []) { for h in handlers.values { h(path) } }
        }
        // Đang đọc thì thư mục nạp lại → kết quả đã cũ, đọc lại một lần.
        if !again.isEmpty { request(again) }
    }
}
