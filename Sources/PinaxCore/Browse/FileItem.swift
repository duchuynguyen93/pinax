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

    /// Key rẻ: được prefetch một lần trong `contentsOfDirectory`.
    static let cheapKeys: [URLResourceKey] = [
        .nameKey, .isDirectoryKey, .isHiddenKey, .isSymbolicLinkKey, .isAliasFileKey,
        .fileSizeKey, .contentModificationDateKey,
    ]
    static let ubiquitousKeys: [URLResourceKey] = [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
    static let resourceKeys: [URLResourceKey] = cheapKeys + [
        .isPackageKey, .creationDateKey, .localizedTypeDescriptionKey, .contentTypeKey, .tagNamesKey,
    ] + ubiquitousKeys

    private static func ubiquitousStatus(_ v: URLResourceValues) -> UbiquitousStatus? {
        guard v.isUbiquitousItem == true else { return nil }
        switch v.ubiquitousItemDownloadingStatus {
        case URLUbiquitousItemDownloadingStatus.current: return .current
        case URLUbiquitousItemDownloadingStatus.downloaded: return .downloaded
        default: return .notDownloaded
        }
    }

    /// Mô tả loại theo UTType, cache theo identifier.
    private static let descriptions = DescriptionCache()
    private final class DescriptionCache: @unchecked Sendable {
        private let lock = NSLock()
        private var map: [String: String] = [:]
        func description(for type: UTType) -> String {
            lock.lock(); defer { lock.unlock() }
            if let d = map[type.identifier] { return d }
            let d = type.localizedDescription ?? ""
            map[type.identifier] = d
            return d
        }
    }

    /// (UTType, mô tả Kind) theo (thư mục?, package?, đuôi): 10k file thường chỉ vài chục đuôi khác nhau,
    /// khỏi tra UTType + viết hoa lại cho từng file.
    private static let typeCache = TypeCache()
    private final class TypeCache: @unchecked Sendable {
        private struct Key: Hashable { let dir: Bool, pkg: Bool, ext: String }
        private let lock = NSLock()
        private var map: [Key: (UTType, String)] = [:]
        func lookup(isDirectory: Bool, isPackage: Bool, ext: String) -> (UTType, String) {
            let key = Key(dir: isDirectory, pkg: isPackage, ext: ext)
            lock.lock()
            if let hit = map[key] { lock.unlock(); return hit }
            lock.unlock()
            let type = FileItem.contentType(isDirectory: isDirectory, isPackage: isPackage, ext: ext)
            let value = (type, FileItem.capitalizingFirst(FileItem.descriptions.description(for: type)))
            lock.lock(); map[key] = value; lock.unlock()
            return value
        }
    }

    /// Loại nội dung suy ra từ đuôi file. Package ưu tiên UTType của đuôi (`.app` → application-bundle → "Application")
    /// trước khi rơi về `.package` chung.
    static func contentType(isDirectory: Bool, isPackage: Bool, ext: String) -> UTType {
        if isDirectory {
            if isPackage {
                if !ext.isEmpty, let t = UTType(filenameExtension: ext), !t.isDynamic, t != .data { return t }
                return .package
            }
            return .folder
        }
        return ext.isEmpty ? .data : (UTType(filenameExtension: ext) ?? .data)
    }

    /// Viết hoa chữ cái đầu của mô tả hệ thống ("folder" → "Folder"), giữ nguyên phần còn lại.
    public static func capitalizingFirst(_ s: String, locale: Locale = .current) -> String {
        guard let first = s.first else { return s }
        return String(first).capitalized(with: locale) + s.dropFirst()
    }

    /// Mô tả loại hiển thị cho cột Kind.
    public static func kindText(isDirectory: Bool, isPackage: Bool, ext: String) -> String {
        capitalizingFirst(descriptions.description(for: contentType(isDirectory: isDirectory, isPackage: isPackage, ext: ext)))
    }

    /// Dựng từ URL vừa lấy từ `contentsOfDirectory` (cache cheapKeys đã có, không xoá cache).
    /// Loại/package suy ra từ đuôi file; tag và iCloud không đọc (trừ khi `readUbiquitous`).
    static func listed(_ url: URL, readUbiquitous: Bool = false) -> FileItem? {
        guard let v = try? url.resourceValues(forKeys: Set(cheapKeys)) else { return nil }
        let name = v.name ?? url.lastPathComponent
        let isDir = v.isDirectory ?? false
        let ext = url.pathExtension
        var isPackage = false
        if isDir, !ext.isEmpty {
            isPackage = (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage ?? false
        }
        let (type, kind) = typeCache.lookup(isDirectory: isDir, isPackage: isPackage, ext: ext)
        var ubiquitous: UbiquitousStatus?
        if readUbiquitous, let u = try? url.resourceValues(forKeys: Set(ubiquitousKeys)) {
            ubiquitous = ubiquitousStatus(u)
        }
        return FileItem(
            url: url, name: name, isDirectory: isDir, isPackage: isPackage,
            isHidden: (v.isHidden ?? false) || name.hasPrefix("."),
            isSymlink: v.isSymbolicLink ?? false, isAlias: v.isAliasFile ?? false,
            size: isDir ? nil : v.fileSize.map(Int64.init),
            modified: v.contentModificationDate, created: nil,
            kindDescription: kind, contentType: type,
            tagNames: [], ubiquitousStatus: ubiquitous)
    }

    /// Bản sao đã đọc mới tag + trạng thái iCloud (listing không đọc hai trường này).
    public func loadingDetails() -> FileItem {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        let v = try? fresh.resourceValues(forKeys: [.tagNamesKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
        return FileItem(
            url: url, name: name, isDirectory: isDirectory, isPackage: isPackage, isHidden: isHidden,
            isSymlink: isSymlink, isAlias: isAlias, size: size, modified: modified, created: created,
            kindDescription: kindDescription, contentType: contentType,
            tagNames: v?.tagNames ?? [], ubiquitousStatus: v.flatMap(Self.ubiquitousStatus))
    }

    /// Đọc resource values mới, đầy đủ (xoá cache của URL trước). nil nếu không đọc được.
    static func read(_ url: URL) -> FileItem? {
        var fresh = url
        fresh.removeAllCachedResourceValues()
        guard let v = try? fresh.resourceValues(forKeys: Set(resourceKeys)) else { return nil }
        let name = v.name ?? url.lastPathComponent
        let isDir = v.isDirectory ?? false
        return FileItem(
            url: url, name: name, isDirectory: isDir, isPackage: v.isPackage ?? false,
            isHidden: (v.isHidden ?? false) || name.hasPrefix("."),
            isSymlink: v.isSymbolicLink ?? false, isAlias: v.isAliasFile ?? false,
            size: isDir ? nil : v.fileSize.map(Int64.init),
            modified: v.contentModificationDate, created: v.creationDate,
            kindDescription: Self.capitalizingFirst(v.localizedTypeDescription ?? ""), contentType: v.contentType,
            tagNames: v.tagNames ?? [], ubiquitousStatus: ubiquitousStatus(v))
    }
}
