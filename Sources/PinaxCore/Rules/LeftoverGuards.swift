import Foundation

/// Các điều kiện bảo thủ của rule leftovers (M4 §3), mỗi điều kiện là một hàm thuần để test không cần máy thật.
public enum LeftoverGuards {
    /// Thành phần đầu kiểu TLD / quốc gia: vendor là thành phần thứ hai.
    static let tldLike: Set<String> = [
        "com", "org", "net", "io", "dev", "app", "co", "me", "xyz", "ru", "pl", "de", "uk", "us", "fr", "jp", "cn",
        "vn", "ai", "so", "tv", "info", "biz", "edu", "gov",
    ]
    /// Không phải tên nhà phát hành thật: bỏ qua kiểm vendor, dựa vào điều kiện tên.
    static let nonVendors: Set<String> = ["electron", "todesktop"]
    /// Tiền tố (chữ thường) của id hệ thống / thành phần dùng chung.
    static let denylist = [
        "com.apple.", "org.cups.", "org.openssh.", "com.microsoft.autoupdate", "com.google.keystone",
        "com.google.googleupdater", "com.adobe.acc", "com.adobe.ccx", "com.adobe.headlights", "com.adobe.crashreporter",
    ]

    // MARK: - 2. Vendor

    public static func vendor(of id: String) -> String {
        let parts = id.lowercased().split(separator: ".").map(String.init)
        guard let first = parts.first else { return "" }
        if tldLike.contains(first), parts.count > 1 { return parts[1] }
        return first
    }

    /// true nếu có app cài cùng vendor với `id` (vendor "electron" / "todesktop" không tính).
    public static func vendorMatches(_ id: String, installedIDs: [String]) -> Bool {
        let v = vendor(of: id)
        guard !v.isEmpty, !nonVendors.contains(v) else { return false }
        return installedIDs.contains { vendor(of: $0) == v }
    }

    // MARK: - 3. Tên app

    /// Chữ thường, chỉ giữ [a-z0-9].
    static func alnum(_ s: String) -> String {
        String(s.lowercased().unicodeScalars.filter { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0))) }.map(Character.init))
    }

    /// Token từ tên hiển thị và tên file .app, độ dài ≥ 4.
    public static func nameTokens(of apps: [InstalledApp]) -> Set<String> {
        var out = Set<String>()
        for app in apps {
            for n in [app.name, app.url.deletingPathExtension().lastPathComponent] {
                let t = alnum(n)
                if t.count >= 4 { out.insert(t) }
            }
        }
        return out
    }

    public static func nameTokenMatches(_ id: String, tokens: Set<String>) -> Bool {
        let flat = alnum(id)
        return tokens.contains { flat.contains($0) }
    }

    // MARK: - 4. CLI

    public static func defaultBinDirs(home: URL) -> [URL] {
        let abs = ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let rel = [".local/bin", ".cargo/bin", "bin", ".bun/bin", ".npm-global/bin", ".deno/bin", "go/bin"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
        return abs + rel
    }

    public static func isCLITool(_ id: String, binDirs: [URL]) -> Bool {
        let v = vendor(of: id)
        let comps = id.lowercased().split(separator: ".").map(String.init)
            .filter { $0.count >= 3 && !tldLike.contains($0) && $0 != v }
        let fm = FileManager.default
        for dir in binDirs {
            for c in comps where fm.isExecutableFile(atPath: dir.appendingPathComponent(c).path) { return true }
        }
        return false
    }

    // MARK: - 5. Denylist

    public static func isDenylisted(_ id: String) -> Bool {
        let l = id.lowercased()
        return denylist.contains { l.hasPrefix($0) }
    }

    // MARK: - 6. Application Support

    /// true nếu có mục nào bên trong sửa từ `cutoff` trở lại đây, hoặc đụng giới hạn `maxEntries` (coi là mới).
    /// Không theo symlink.
    public static func hasRecentContent(_ root: URL, since cutoff: Date, maxEntries: Int = 3000) -> Bool {
        let fm = FileManager.default
        var stack = [root]
        var seen = 0
        while let dir = stack.popLast() {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names {
                seen += 1
                if seen > maxEntries { return true }
                let url = dir.appendingPathComponent(name)
                var st = stat()
                guard lstat(url.path, &st) == 0 else { continue }
                let mtime = Date(timeIntervalSince1970: TimeInterval(st.st_mtimespec.tv_sec))
                if mtime >= cutoff { return true }
                if (st.st_mode & S_IFMT) == S_IFDIR { stack.append(url) }
            }
        }
        return false
    }
}

/// Spotlight: mọi bundle app trong một lần hỏi. Lỗi / quá giờ → [] (im lặng).
public enum SpotlightInstalledApps {
    public typealias Provider = @Sendable () -> [InstalledApp]

    public static let defaultProvider: Provider = { query(timeout: 5) }

    static func query(timeout: TimeInterval) -> [InstalledApp] {
        guard let data = ProcessRunner.run("/usr/bin/mdfind", ["-0", "-attr", "kMDItemCFBundleIdentifier",
                                                               "kMDItemContentType == 'com.apple.application-bundle'"],
                                           timeout: timeout),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// Mỗi bản ghi (ngăn bởi NUL hoặc xuống dòng): `<path>   kMDItemCFBundleIdentifier = <id>`.
    static func parse(_ text: String) -> [InstalledApp] {
        let sep = "   kMDItemCFBundleIdentifier = "
        var out: [InstalledApp] = []
        for record in text.split(whereSeparator: { $0 == "\0" || $0 == "\n" }) {
            guard let r = record.range(of: sep) else { continue }
            let path = String(record[..<r.lowerBound])
            let id = String(record[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            guard path.hasSuffix(".app"), !id.isEmpty, id != "(null)" else { continue }
            let url = URL(fileURLWithPath: path)
            out.append(InstalledApp(url: url, bundleID: id, name: url.deletingPathExtension().lastPathComponent))
        }
        return out
    }
}
