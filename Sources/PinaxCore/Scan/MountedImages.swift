import Foundation

public protocol MountedImagesProviding: Sendable {
    /// Đường dẫn các file ảnh đĩa đang mount (đã resolve symlink).
    func imagePaths() -> Set<URL>
}

/// Parse `hdiutil info -plist` → các `image-path`. Lỗi → tập rỗng.
public struct MountedImages: MountedImagesProviding {
    public init() {}

    public func imagePaths() -> Set<URL> {
        guard let data = ProcessRunner.run("/usr/bin/hdiutil", ["info", "-plist"], timeout: 15),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let root = plist as? [String: Any],
              let images = root["images"] as? [[String: Any]] else { return [] }
        var out = Set<URL>()
        for image in images {
            if let path = image["image-path"] as? String {
                out.insert(URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL)
            }
        }
        return out
    }
}
