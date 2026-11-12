import Foundation

/// Một dịch vụ lưu trữ đám mây được macOS gắn vào `~/Library/CloudStorage`.
public struct CloudLocation: Equatable, Sendable {
    public let url: URL
    /// Tên hiển thị của dịch vụ ("Google Drive", "Dropbox"...); dịch vụ lạ → tên thư mục nguyên gốc.
    public let service: String
    /// Email / tên tổ chức sau dấu "-" trong tên thư mục, nếu có.
    public let account: String?
}

/// Liệt kê các thư mục dịch vụ đám mây. Thuần, chỉ đọc; `root` được tiêm để test.
public enum CloudLocations {
    private static let known: [String: String] = [
        "GoogleDrive": "Google Drive", "OneDrive": "OneDrive", "Dropbox": "Dropbox", "Box": "Box",
    ]

    public static func defaultRoot(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appendingPathComponent("Library/CloudStorage", isDirectory: true)
    }

    public static func list(root: URL) -> [CloudLocation] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return [] }
        var out: [CloudLocation] = []
        for url in urls {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            out.append(parse(url))
        }
        return out.sorted {
            let c = $0.service.localizedStandardCompare($1.service)
            return c != .orderedSame ? c == .orderedAscending : ($0.account ?? "").localizedStandardCompare($1.account ?? "") == .orderedAscending
        }
    }

    static func parse(_ url: URL) -> CloudLocation {
        let name = url.lastPathComponent
        let parts = name.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first, let service = known[String(first)] else {
            return CloudLocation(url: url, service: name, account: nil)
        }
        let account = parts.count > 1 && !parts[1].isEmpty ? String(parts[1]) : nil
        return CloudLocation(url: url, service: service, account: account)
    }
}
