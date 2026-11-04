import AppKit
import PinaxCore

/// Icon 16 pt cho danh sách. Chỉ dùng trên main thread.
/// Thư mục / package / link tra theo đường dẫn (có icon riêng); file thường tra theo loại nội dung để khỏi gọi
/// `icon(forFile:)` cho từng file trong thư mục hàng nghìn mục.
@MainActor
final class IconCache {
    static let shared = IconCache()
    private let cache = NSCache<NSString, NSImage>()

    func icon(for item: FileItem, size: CGFloat = 16) -> NSImage {
        let byPath = item.isDirectory || item.isPackage || item.isSymlink || item.isAlias || item.contentType == nil
        let key = (byPath ? "p:" + item.url.path : "t:" + (item.contentType?.identifier ?? "")) + "@\(Int(size))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let base = byPath ? NSWorkspace.shared.icon(forFile: item.url.path) : NSWorkspace.shared.icon(for: item.contentType!)
        return store(base, key: key, size: size)
    }

    func icon(forPath path: String, size: CGFloat = 16) -> NSImage {
        let key = "p:" + path + "@\(Int(size))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        return store(NSWorkspace.shared.icon(forFile: path), key: key, size: size)
    }

    private func store(_ image: NSImage, key: NSString, size: CGFloat) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.size = NSSize(width: size, height: size)
        cache.setObject(copy, forKey: key)
        return copy
    }
}
