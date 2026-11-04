import Foundation

/// Sắp xếp danh sách file. Hoà thì xếp theo tên tăng dần để thứ tự ổn định.
public struct FileSort: Equatable, Sendable {
    public enum Key: String, Sendable, CaseIterable { case name, modified, size, kind }

    public var key: Key
    public var ascending: Bool
    public var foldersFirst: Bool

    public init(key: Key = .name, ascending: Bool = true, foldersFirst: Bool = true) {
        self.key = key
        self.ascending = ascending
        self.foldersFirst = foldersFirst
    }

    public func sorted(_ items: [FileItem]) -> [FileItem] {
        items.sorted { a, b in
            if foldersFirst, a.isNavigableFolder != b.isNavigableFolder { return a.isNavigableFolder }
            let r = compare(a, b)
            if r == .orderedSame { return Self.byName(a, b) == .orderedAscending }
            return ascending ? r == .orderedAscending : r == .orderedDescending
        }
    }

    private func compare(_ a: FileItem, _ b: FileItem) -> ComparisonResult {
        switch key {
        case .name: return Self.byName(a, b)
        case .modified: return Self.compare(a.modified, b.modified)
        case .size: return Self.compare(a.size, b.size)
        case .kind:
            let r = a.kindDescription.localizedStandardCompare(b.kindDescription)
            return r
        }
    }

    private static func byName(_ a: FileItem, _ b: FileItem) -> ComparisonResult {
        a.name.localizedStandardCompare(b.name)
    }

    /// nil (không rõ) xếp như nhỏ nhất.
    private static func compare<T: Comparable>(_ a: T?, _ b: T?) -> ComparisonResult {
        switch (a, b) {
        case (nil, nil): return .orderedSame
        case (nil, _): return .orderedAscending
        case (_, nil): return .orderedDescending
        case let (x?, y?): return x < y ? .orderedAscending : (x > y ? .orderedDescending : .orderedSame)
        }
    }
}
