import Foundation

/// Deny-list cứng (§1.3). Mọi đường dẫn bị resolve symlink trước khi kiểm.
/// So sánh không phân biệt hoa/thường (APFS mặc định): quá chặt trên ổ case-sensitive còn hơn để lọt.
public struct PathGuard: Sendable {
    public static let pinaxBundleID = "com.duchuynguyen93.pinax"

    /// Kiểm một thư mục `/Volumes/<tên>` có phải ổ ngoài (không phải ổ khởi động) hay không. Tiêm được để test.
    public typealias VolumeCheck = @Sendable (URL) -> Bool

    private let home: [String]
    private let applicationsRoot: [String]
    private let volumesRoot: [String]
    private let deniedExact: Set<[String]>
    private let trash: [String]
    private let mobileDocuments: [String]
    private let isExternalVolume: VolumeCheck

    public init(home: URL,
                applicationsRoot: URL = URL(fileURLWithPath: "/Applications"),
                volumesRoot: URL = URL(fileURLWithPath: "/Volumes"),
                isExternalVolume: @escaping VolumeCheck = PathGuard.defaultIsExternalVolume) {
        let h = Self.components(home)
        let a = Self.components(applicationsRoot)
        let v = Self.components(volumesRoot)
        self.home = h
        self.applicationsRoot = a
        self.volumesRoot = v
        self.isExternalVolume = isExternalVolume
        self.trash = h + [".trash"]
        self.mobileDocuments = h + ["library", "mobile documents"]
        var denied: Set<[String]> = [[], ["system"], ["library"], a, h, v]
        // Gốc hệ thống (M2 §3.2). Mọi thứ bên trong cũng bị chặn vì danh sách cho phép bên dưới là whitelist.
        for root in ["usr", "bin", "sbin", "private", "opt", "cores"] { denied.insert([root]) }
        for sub in ["library", "desktop", "documents", "downloads", "movies", "pictures", "music", ".trash"] {
            denied.insert(h + [sub])
        }
        denied.insert(h + ["library", "mobile documents"])
        self.deniedExact = denied
    }

    public func isAllowed(_ url: URL) -> Bool {
        let resolved = Self.resolve(url)
        let c = Self.lowered(resolved)
        if deniedExact.contains(c) { return false }
        // Bên trong Thùng rác: cấm hết.
        if Self.hasPrefix(c, trash) { return false }
        // Gốc container iCloud: ~/Library/Mobile Documents/<container>
        if Self.hasPrefix(c, mobileDocuments) && c.count <= mobileDocuments.count + 1 { return false }
        // Chỉ cho phép nằm NGHIÊM NGẶT trong home, /Applications hoặc một ổ ngoài.
        let inHome = c.count > home.count && Self.hasPrefix(c, home)
        let inApps = c.count > applicationsRoot.count && Self.hasPrefix(c, applicationsRoot)
        if inHome || inApps { return true }
        return isInsideExternalVolume(c, resolved)
    }

    /// `/Volumes/<tên>/<ít nhất một cấp>`; gốc volume bị chặn. Thùng rác / chỉ mục của chính ổ đó cũng bị chặn.
    private func isInsideExternalVolume(_ c: [String], _ resolved: URL) -> Bool {
        guard c.count > volumesRoot.count + 1, Self.hasPrefix(c, volumesRoot) else { return false }
        if [".trashes", ".spotlight-v100", ".fseventsd"].contains(c[volumesRoot.count + 1]) { return false }
        // Dùng tên gốc (đúng hoa/thường) để hỏi hệ thống về volume.
        let original = resolved.pathComponents.filter { $0 != "/" }
        var volume = URL(fileURLWithPath: "/", isDirectory: true)
        // volumesRoot đã resolve nên dựng lại từ đầu path đã resolve: lấy đúng (volumesRoot.count + 1) cấp.
        for part in original.prefix(volumesRoot.count + 1) { volume.appendPathComponent(part, isDirectory: true) }
        return isExternalVolume(volume)
    }

    /// Mặc định: `volumeIsInternal == false` hoặc `volumeIsRemovable == true`, và không phải ổ khởi động.
    public static let defaultIsExternalVolume: VolumeCheck = { volume in
        let keys: Set<URLResourceKey> = [.volumeIsInternalKey, .volumeIsRemovableKey, .volumeURLKey]
        var v = volume
        v.removeAllCachedResourceValues()
        guard let values = try? v.resourceValues(forKeys: keys) else { return false }
        var root = URL(fileURLWithPath: "/")
        root.removeAllCachedResourceValues()
        if let startup = try? root.resourceValues(forKeys: [.volumeURLKey]).volume,
           let this = values.volume,
           startup.standardizedFileURL.path == this.standardizedFileURL.path { return false }
        return values.volumeIsInternal == false || values.volumeIsRemovable == true
    }

    /// App không bao giờ được đụng tới: `com.apple.*` và chính Pinax.
    public static func isProtectedApp(bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased() else { return false }
        return id.hasPrefix("com.apple.") || id == pinaxBundleID
    }

    private static func resolve(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func lowered(_ resolved: URL) -> [String] {
        resolved.pathComponents.filter { $0 != "/" }.map { $0.lowercased() }
    }

    private static func components(_ url: URL) -> [String] {
        lowered(resolve(url))
    }

    private static func hasPrefix(_ c: [String], _ prefix: [String]) -> Bool {
        c.count >= prefix.count && Array(c.prefix(prefix.count)) == prefix
    }
}
