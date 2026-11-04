import Foundation

/// Liệt kê một thư mục (không đệ quy, không theo symlink).
public enum DirectoryLister {
    /// Một lần `contentsOfDirectory` với đủ key. Ném `CancellationError` nếu task bị huỷ.
    /// Chưa sắp xếp: dùng `FileSort`. Mục không đọc được thuộc tính bị bỏ qua (không phá cả thư mục).
    public static func list(_ url: URL, showHidden: Bool) async throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: FileItem.resourceKeys, options: [])
        var items: [FileItem] = []
        items.reserveCapacity(urls.count)
        for child in urls {
            try Task.checkCancellation()
            guard let item = FileItem.read(child) else { continue }
            if !showHidden && item.isHidden { continue }
            items.append(item)
        }
        return items
    }
}
