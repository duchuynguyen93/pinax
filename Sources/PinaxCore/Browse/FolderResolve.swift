import Foundation

/// Tìm thư mục còn tồn tại gần nhất khi thư mục đang xem bị xoá / đổi tên.
public enum FolderResolve {
    /// Đi ngược lên cha cho tới khi gặp một thư mục có thật. Luôn trả về ít nhất `/`.
    public static func nearestExistingFolder(_ url: URL) -> URL {
        var path = url.standardizedFileURL.path
        while path != "/" && !path.isEmpty {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
            path = (path as NSString).deletingLastPathComponent
        }
        return URL(fileURLWithPath: "/", isDirectory: true)
    }
}
