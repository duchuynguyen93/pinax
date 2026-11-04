import Foundation

/// Tìm kiếm Spotlight; protocol để test không đụng Spotlight thật.
public protocol SpotlightSearching: Sendable {
    /// nil = hết giờ / lỗi / exit ≠ 0 → caller dùng `DirectoryWalker`.
    func find(query: String, in root: URL) -> [URL]?
}

/// `/usr/bin/mdfind -0 -onlyin <root> <query>`, timeout 20 s.
public struct SpotlightQuery: SpotlightSearching {
    public var timeout: TimeInterval

    public init(timeout: TimeInterval = 20) { self.timeout = timeout }

    public func find(query: String, in root: URL) -> [URL]? {
        guard let data = ProcessRunner.run("/usr/bin/mdfind", ["-0", "-onlyin", root.path, query],
                                           timeout: timeout) else { return nil }
        return data.split(separator: 0).compactMap { chunk in
            String(data: Data(chunk), encoding: .utf8).map { URL(fileURLWithPath: $0) }
        }
    }
}
