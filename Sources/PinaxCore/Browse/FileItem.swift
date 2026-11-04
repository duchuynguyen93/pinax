import Foundation
import UniformTypeIdentifiers

/// Trạng thái iCloud của một mục (nil nếu không nằm trong iCloud).
public enum UbiquitousStatus: Sendable, Equatable {
    /// Bản cục bộ mới nhất.
    case current
    /// Có bản cục bộ nhưng có thể cũ.
    case downloaded
    /// Chỉ có trên iCloud (placeholder).
    case notDownloaded
}

/// Một dòng trong trình duyệt. Dữ liệu đọc một lần lúc liệt kê, không theo symlink.
public struct FileItem: Identifiable, Hashable, Sendable {
    public var id: URL { url }
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isPackage: Bool
    public let isHidden: Bool
    public let isSymlink: Bool
    public let isAlias: Bool
    /// Kích thước logic của file; nil với thư mục (tính nền ở tầng UI).
    public let size: Int64?
    public let modified: Date?
    public let created: Date?
    public let kindDescription: String
    public let contentType: UTType?
    public let tagNames: [String]
    public let ubiquitousStatus: UbiquitousStatus?

    public init(url: URL, name: String, isDirectory: Bool, isPackage: Bool = false, isHidden: Bool = false,
                isSymlink: Bool = false, isAlias: Bool = false, size: Int64? = nil, modified: Date? = nil,
                created: Date? = nil, kindDescription: String = "", contentType: UTType? = nil,
                tagNames: [String] = [], ubiquitousStatus: UbiquitousStatus? = nil) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.isSymlink = isSymlink
        self.isAlias = isAlias
        self.size = size
        self.modified = modified
        self.created = created
        self.kindDescription = kindDescription
        self.contentType = contentType
        self.tagNames = tagNames
        self.ubiquitousStatus = ubiquitousStatus
    }

    /// Thư mục thật sự đi vào được (package như `.app` coi là file).
    public var isNavigableFolder: Bool { isDirectory && !isPackage }

    static let resourceKeys: [URLResourceKey] = [
        .nameKey, .isDirectoryKey, .isPackageKey, .isHiddenKey, .isSymbolicLinkKey, .isAliasFileKey,
        .fileSizeKey, .contentModificationDateKey, .creationDateKey, .localizedTypeDescriptionKey,
        .contentTypeKey, .tagNamesKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey,
    ]

    /// Đọc resource values mới (xoá cache của URL trước). nil nếu không đọc được.
    static func read(_ url: URL) -> FileItem? {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        guard let v = try? fresh.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
        let name = v.name ?? url.lastPathComponent
        let isDir = v.isDirectory ?? false
        let ubiquitous: UbiquitousStatus?
        if v.isUbiquitousItem == true {
            switch v.ubiquitousItemDownloadingStatus {
            case URLUbiquitousItemDownloadingStatus.current: ubiquitous = .current
            case URLUbiquitousItemDownloadingStatus.downloaded: ubiquitous = .downloaded
            default: ubiquitous = .notDownloaded
            }
        } else {
            ubiquitous = nil
        }
        return FileItem(
            url: url, name: name, isDirectory: isDir, isPackage: v.isPackage ?? false,
            isHidden: (v.isHidden ?? false) || name.hasPrefix("."),
            isSymlink: v.isSymbolicLink ?? false, isAlias: v.isAliasFile ?? false,
            size: isDir ? nil : v.fileSize.map(Int64.init),
            modified: v.contentModificationDate, created: v.creationDate,
            kindDescription: v.localizedTypeDescription ?? "", contentType: v.contentType,
            tagNames: v.tagNames ?? [], ubiquitousStatus: ubiquitous)
    }
}
