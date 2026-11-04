import Foundation

/// Deny-list cứng (§1.3). Mọi đường dẫn bị resolve symlink trước khi kiểm.
/// So sánh không phân biệt hoa/thường (APFS mặc định): quá chặt trên ổ case-sensitive còn hơn để lọt.
public struct PathGuard: Sendable {
    public static let pinaxBundleID = "com.duchuynguyen93.pinax"

    private let home: [String]
    private let applicationsRoot: [String]
    private let deniedExact: Set<[String]>
    private let trash: [String]
    private let mobileDocuments: [String]

    public init(home: URL, applicationsRoot: URL = URL(fileURLWithPath: "/Applications")) {
        let h = Self.components(home)
        let a = Self.components(applicationsRoot)
        self.home = h
        self.applicationsRoot = a
        self.trash = h + [".trash"]
        self.mobileDocuments = h + ["library", "mobile documents"]
        var denied: Set<[String]> = [[], ["system"], ["library"], a, h]
        for sub in ["library", "desktop", "documents", "downloads", "movies", "pictures", "music", ".trash"] {
            denied.insert(h + [sub])
        }
        denied.insert(h + ["library", "mobile documents"])
        self.deniedExact = denied
    }

    public func isAllowed(_ url: URL) -> Bool {
        let c = Self.components(url)
        if deniedExact.contains(c) { return false }
        // Bên trong Thùng rác: cấm hết.
        if Self.hasPrefix(c, trash) { return false }
        // Gốc container iCloud: ~/Library/Mobile Documents/<container>
        if Self.hasPrefix(c, mobileDocuments) && c.count <= mobileDocuments.count + 1 { return false }
        // Chỉ cho phép nằm NGHIÊM NGẶT trong home hoặc trong /Applications.
        let inHome = c.count > home.count && Self.hasPrefix(c, home)
        let inApps = c.count > applicationsRoot.count && Self.hasPrefix(c, applicationsRoot)
        return inHome || inApps
    }

    /// App không bao giờ được đụng tới: `com.apple.*` và chính Pinax.
    public static func isProtectedApp(bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased() else { return false }
        return id.hasPrefix("com.apple.") || id == pinaxBundleID
    }

    private static func components(_ url: URL) -> [String] {
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL
        return resolved.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
    }

    private static func hasPrefix(_ c: [String], _ prefix: [String]) -> Bool {
        c.count >= prefix.count && Array(c.prefix(prefix.count)) == prefix
    }
}
