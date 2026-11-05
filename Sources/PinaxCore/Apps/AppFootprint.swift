import Foundation
import Security

public enum FootprintMatch: Sendable {
    case bundleID, helper, teamGroup, name
}

public struct FootprintItem: Sendable, Hashable {
    public let url: URL
    /// Thư mục cha tính từ ~/Library, vd "Caches", "Preferences/ByHost".
    public let location: String
    public let match: FootprintMatch
    public let preselected: Bool

    public init(url: URL, location: String, match: FootprintMatch, preselected: Bool) {
        self.url = url
        self.location = location
        self.match = match
        self.preselected = preselected
    }
}

extension FootprintMatch: Hashable {}

/// Mục liên quan tới một app trong ~/Library (M4 §2). Không đệ quy, không theo symlink.
public enum AppFootprint {
    /// Thư mục khớp theo bundle id (Containers có riêng vì rule leftovers không đọc).
    static let idLocations = [
        "Application Support", "Caches", "Preferences", "Preferences/ByHost", "Saved Application State",
        "HTTPStorages", "WebKit", "Logs", "Cookies", "LaunchAgents",
    ]
    static let nameLocations = ["Application Support", "Caches", "Logs"]

    // MARK: - Tên mục → bundle id

    /// Bỏ đuôi theo thư mục rồi kiểm reverse-DNS. nil nếu không hợp lệ.
    public static func bundleIDFromEntryName(_ name: String, in location: String) -> String? {
        guard let id = strippedID(name, in: location), isReverseDNS(id) else { return nil }
        return id
    }

    static func isReverseDNS(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        return parts.allSatisfy { p in
            !p.isEmpty && p.unicodeScalars.allSatisfy { ($0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains(Character($0)))) || $0 == "-" || $0 == "_" }
        }
    }

    /// Bỏ đuôi, không kiểm hợp lệ.
    static func strippedID(_ name: String, in location: String) -> String? {
        switch location {
        case "Preferences", "LaunchAgents":
            return dropSuffix(name, ".plist")
        case "Preferences/ByHost":
            guard let base = dropSuffix(name, ".plist") else { return nil }
            return dropHostSuffix(base) ?? base
        case "Saved Application State":
            return dropSuffix(name, ".savedState")
        case "Cookies":
            return dropSuffix(name, ".binarycookies")
        case "HTTPStorages":
            return dropSuffix(name, ".binarycookies") ?? name
        default:
            return name
        }
    }

    private static func dropSuffix(_ s: String, _ suffix: String) -> String? {
        s.lowercased().hasSuffix(suffix.lowercased()) ? String(s.dropLast(suffix.count)) : nil
    }

    /// `<id>.<UUID>` hoặc `<id>.<12 hex>` → `<id>`.
    private static func dropHostSuffix(_ base: String) -> String? {
        guard let dot = base.lastIndex(of: ".") else { return nil }
        let tail = base[base.index(after: dot)...]
        if isHexUUID(String(tail)) || isHex(String(tail), count: 12) { return String(base[..<dot]) }
        return nil
    }

    private static func isHex(_ s: String, count: Int) -> Bool {
        s.count == count && s.allSatisfy { $0.isHexDigit }
    }

    private static func isHexUUID(_ s: String) -> Bool {
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        let sizes = [8, 4, 4, 4, 12]
        guard parts.count == 5 else { return false }
        return zip(parts, sizes).allSatisfy { isHex(String($0), count: $1) }
    }

    // MARK: - Tìm mục

    public static func items(for app: InstalledApp, teamID: String?, otherAppsWithSameTeam: Bool, library: URL) -> [FootprintItem] {
        var out: [FootprintItem] = []
        var seen = Set<String>()
        func add(_ item: FootprintItem) {
            if seen.insert(item.url.path).inserted { out.append(item) }
        }

        if let id = app.bundleID?.lowercased(), !id.isEmpty {
            for loc in idLocations + ["Containers"] {
                for (name, url) in entries(library, loc) {
                    guard let entryID = strippedID(name, in: loc)?.lowercased() else { continue }
                    if entryID == id {
                        add(FootprintItem(url: url, location: loc, match: .bundleID, preselected: true))
                    } else if entryID.hasPrefix(id + ".") {
                        add(FootprintItem(url: url, location: loc, match: .helper, preselected: true))
                    }
                }
            }
        }

        if let team = teamID, !team.isEmpty {
            for (name, url) in entries(library, "Group Containers") where name.hasPrefix(team + ".") {
                add(FootprintItem(url: url, location: "Group Containers", match: .teamGroup, preselected: false))
            }
        }

        var names = Set<String>()
        for n in [app.name, app.url.deletingPathExtension().lastPathComponent] where n.count >= 3 { names.insert(n.lowercased()) }
        if !names.isEmpty {
            for loc in nameLocations {
                for (name, url) in entries(library, loc) where names.contains(name.lowercased()) {
                    add(FootprintItem(url: url, location: loc, match: .name, preselected: false))
                }
            }
        }
        return out
    }

    /// Mục cấp 1 của `~/Library/<loc>`; bỏ qua nếu thiếu / là symlink; mục là symlink cũng bỏ (lstat).
    static func entries(_ library: URL, _ loc: String) -> [(String, URL)] {
        let dir = library.appendingPathComponent(loc, isDirectory: true)
        guard isRealDirectory(dir),
              let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return names.sorted().compactMap { name in
            let url = dir.appendingPathComponent(name)
            var st = stat()
            guard lstat(url.path, &st) == 0, (st.st_mode & S_IFMT) != S_IFLNK else { return nil }
            return (name, url)
        }
    }

    private static func isRealDirectory(_ url: URL) -> Bool {
        var st = stat()
        return lstat(url.path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR
    }
}

public enum TeamID {
    /// Team id từ chữ ký tĩnh của .app; nil nếu không ký / app Apple.
    public static func of(appURL: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(appURL as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
