import AppKit
@preconcurrency import QuickLookThumbnailing
import UniformTypeIdentifiers
import PinaxCore

/// Cache thumbnail dùng chung mọi cửa sổ: khoá (đường dẫn, mtime, cỡ, scale). Không ghi đĩa.
@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.totalCostLimit = 128 * 1024 * 1024
        return c
    }()
    /// Mục QuickLook không tạo được thumbnail → khỏi hỏi lại.
    private var failed = Set<String>()

    static func key(_ item: FileItem, points: CGFloat, scale: CGFloat) -> String {
        "\(item.url.path)|\(item.modified?.timeIntervalSinceReferenceDate ?? 0)|\(item.size ?? 0)|\(Int(points))|\(Int(scale))"
    }

    func image(forKey key: String) -> NSImage? { cache.object(forKey: key as NSString) }
    func isFailed(_ key: String) -> Bool { failed.contains(key) }
    func markFailed(_ key: String) { failed.insert(key) }
    func store(_ image: NSImage, key: String, cost: Int) { cache.setObject(image, forKey: key as NSString, cost: cost) }

    private static let extraExts: Set<String> = ["pages", "numbers", "key", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "rtfd", "epub"]
    private static let types: [UTType] = [.image, .movie, .pdf, .presentation, .spreadsheet, .compositeContent, .plainText, .rtf, .html]

    /// Loại file nên xin thumbnail (ảnh, video, PDF, tài liệu). Thư mục, app, file nhị phân thường dùng icon hệ thống.
    static func wants(_ item: FileItem) -> Bool {
        guard !item.isDirectory, !item.isPackage else { return false }
        guard let t = item.contentType else { return false }
        if extraExts.contains(item.url.pathExtension.lowercased()) { return true }
        return types.contains { t.conforms(to: $0) }
    }
}

/// Một view (list hoặc icon) giữ một requester: theo dõi request đang chạy theo "chủ" (cell), huỷ khi cell tái dùng / đổi thư mục.
@MainActor
final class ThumbnailRequester {
    private var active: [ObjectIdentifier: QLThumbnailGenerator.Request] = [:]

    /// Ảnh đã có trong cache (nếu có).
    func cached(_ item: FileItem, points: CGFloat, scale: CGFloat) -> NSImage? {
        ThumbnailCache.shared.image(forKey: ThumbnailCache.key(item, points: points, scale: scale))
    }

    /// Xin thumbnail không chặn main; `completion` chạy trên main, chỉ khi request chưa bị huỷ.
    func load(for owner: AnyObject, item: FileItem, points: CGFloat, scale: CGFloat, completion: @escaping (NSImage) -> Void) {
        cancel(owner)
        guard ThumbnailCache.wants(item) else { return }
        let cache = ThumbnailCache.shared
        let key = ThumbnailCache.key(item, points: points, scale: scale)
        if let hit = cache.image(forKey: key) { completion(hit); return }
        guard !cache.isFailed(key) else { return }

        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: CGSize(width: points, height: points),
                                                   scale: scale, representationTypes: .thumbnail)
        let id = ObjectIdentifier(owner)
        active[id] = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak self] rep, _ in
            let cg = rep?.cgImage
            Task { @MainActor in
                guard let self, self.active[id] === request else { return } // đã huỷ / cell đã đổi
                self.active[id] = nil
                guard let cg else { cache.markFailed(key); return }
                let image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
                cache.store(image, key: key, cost: cg.width * cg.height * 4)
                completion(image)
            }
        }
    }

    func cancel(_ owner: AnyObject) {
        if let r = active.removeValue(forKey: ObjectIdentifier(owner)) { QLThumbnailGenerator.shared.cancel(r) }
    }

    func cancelAll() {
        for r in active.values { QLThumbnailGenerator.shared.cancel(r) }
        active.removeAll()
    }
}
