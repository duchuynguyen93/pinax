import Foundation

/// Liệt kê một thư mục (không đệ quy, không theo symlink).
public enum DirectoryLister {
    /// Một lần `contentsOfDirectory` với key rẻ; loại suy từ đuôi, tag/iCloud không đọc (trừ trong Mobile Documents). Ném `CancellationError` nếu task bị huỷ.
    /// Chưa sắp xếp: dùng `FileSort`. Mục không đọc được thuộc tính bị bỏ qua (không phá cả thư mục).
    public static func list(_ url: URL, showHidden: Bool) async throws -> [FileItem] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: FileItem.cheapKeys, options: [])
        let mobile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents").path
        let inICloud = url.standardizedFileURL.path.hasPrefix(mobile)
        var items: [FileItem] = []
        items.reserveCapacity(urls.count)
        for child in urls {
            try Task.checkCancellation()
            guard let item = FileItem.listed(child, readUbiquitous: inICloud) else { continue }
            if !showHidden && item.isHidden { continue }
            items.append(item)
        }
        return items
    }
}
