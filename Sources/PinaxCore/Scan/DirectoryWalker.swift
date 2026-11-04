import Foundation

/// Duyệt thư mục có giới hạn độ sâu. Không theo symlink (bỏ qua hẳn), không đi vào package.
public struct DirectoryWalker {
    public struct Entry {
        public let url: URL
        public let isDirectory: Bool
        /// Package (.app, ...) được báo như một entry nhưng không đi vào trong.
        public let isPackage: Bool
        /// 1 = con trực tiếp của root.
        public let depth: Int
    }

    public var maxDepth: Int
    public var includeHidden: Bool
    public var includeDirectories: Bool

    public init(maxDepth: Int = .max, includeHidden: Bool = false, includeDirectories: Bool = false) {
        self.maxDepth = maxDepth
        self.includeHidden = includeHidden
        self.includeDirectories = includeDirectories
    }

    /// Gọi `visit` cho từng entry. `visit` trả false cho thư mục = không đi vào thư mục đó.
    /// Ném `CancellationError` nếu task bị huỷ.
    public func walk(_ root: URL, visit: (Entry) throws -> Bool) throws {
        try walk(root, depth: 1, visit: visit)
    }

    /// Tiện ích: gom tất cả file thường.
    public func files(under root: URL) throws -> [URL] {
        var out: [URL] = []
        try walk(root) { entry in
            if !entry.isDirectory && !entry.isPackage { out.append(entry.url) }
            return true
        }
        return out
    }

    private func walk(_ dir: URL, depth: Int, visit: (Entry) throws -> Bool) throws {
        guard depth <= maxDepth else { return }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        let opts: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let children = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: keys, options: opts)) ?? []
        for child in children {
            try Task.checkCancellation()
            guard let v = try? child.resourceValues(forKeys: Set(keys)) else { continue }
            if v.isSymbolicLink == true { continue }
            let isPackage = v.isPackage == true
            let isDir = v.isDirectory == true && !isPackage
            if isDir {
                var descend = true
                if includeDirectories {
                    descend = try visit(Entry(url: child, isDirectory: true, isPackage: false, depth: depth))
                }
                if descend { try walk(child, depth: depth + 1, visit: visit) }
            } else {
                _ = try visit(Entry(url: child, isDirectory: false, isPackage: isPackage, depth: depth))
            }
        }
    }
}
