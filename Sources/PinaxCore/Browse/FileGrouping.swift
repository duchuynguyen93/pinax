import Foundation
import UniformTypeIdentifiers

/// Kiểu nhóm của danh sách (View ▸ Group By).
public enum GroupBy: String, CaseIterable, Sendable { case none, kind, modified }

/// Nhóm theo loại, thứ tự enum = thứ tự hiển thị.
public enum KindGroup: Int, CaseIterable, Sendable, Comparable {
    case folder, application, document, pdf, spreadsheet, presentation, image, movie, music,
         archive, diskImage, sourceCode, other
    public static func < (a: KindGroup, b: KindGroup) -> Bool { a.rawValue < b.rawValue }
}

/// Nhóm theo ngày sửa.
public enum DateGroup: Hashable, Sendable {
    case today, yesterday, previous7Days, previous30Days
    case month(year: Int, month: Int)
    case year(Int)
    case unknown
}

public enum GroupKey: Hashable, Sendable { case kind(KindGroup), date(DateGroup) }

public struct FileGroup: Equatable, Sendable {
    public let key: GroupKey
    public let items: [FileItem]
}

/// Chia danh sách đã sắp thành các nhóm. Thuần, O(n).
public enum FileGrouping {
    /// Cache loại theo `contentType.identifier`: 10k file chỉ vài chục UTType khác nhau, `conforms(to:)` khá đắt.
    private static let cache = KindCache()
    private final class KindCache: @unchecked Sendable {
        private let lock = NSLock()
        private var map: [String: KindGroup] = [:]
        func lookup(_ type: UTType) -> KindGroup {
            lock.lock()
            if let hit = map[type.identifier] { lock.unlock(); return hit }
            lock.unlock()
            let k = FileGrouping.classify(type)
            lock.lock(); map[type.identifier] = k; lock.unlock()
            return k
        }
    }

    private static func classify(_ t: UTType) -> KindGroup {
        if t.conforms(to: .application) || t.conforms(to: .applicationBundle) { return .application }
        if t.conforms(to: .pdf) { return .pdf }
        if t.conforms(to: .diskImage) { return .diskImage }
        if t.conforms(to: .archive) { return .archive }
        // SVG vừa là image vừa là xml → xếp vào Hình ảnh.
        if t.conforms(to: .image) { return .image }
        if t.conforms(to: .sourceCode) || t.conforms(to: .script) || t.conforms(to: .shellScript)
            || t.conforms(to: .json) || t.conforms(to: .xml) || t.conforms(to: .yaml) { return .sourceCode }
        if t.conforms(to: .spreadsheet) { return .spreadsheet }
        if t.conforms(to: .presentation) { return .presentation }
        if t.conforms(to: .movie) || t.conforms(to: .video)
            || (t.conforms(to: .audiovisualContent) && !t.conforms(to: .audio)) { return .movie }
        if t.conforms(to: .audio) { return .music }
        if t.conforms(to: .text) || t.conforms(to: .compositeContent) { return .document }
        return .other
    }

    public static func kindGroup(_ item: FileItem) -> KindGroup {
        if item.isNavigableFolder { return .folder }
        guard let type = item.contentType else { return .other }
        return cache.lookup(type)
    }

    public static func dateGroup(_ date: Date?, now: Date, calendar: Calendar) -> DateGroup {
        guard let d = date else { return .unknown }
        let start = calendar.startOfDay(for: now)
        if d >= start { return .today }
        func back(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: start) ?? start }
        if d >= back(1) { return .yesterday }
        if d >= back(7) { return .previous7Days }
        if d >= back(30) { return .previous30Days }
        let c = calendar.dateComponents([.year, .month], from: d)
        let y = c.year ?? 0
        if y == calendar.component(.year, from: now) { return .month(year: y, month: c.month ?? 1) }
        return .year(y)
    }

    /// Thứ hạng hiển thị của nhóm ngày (nhỏ = trên).
    private static func rank(_ g: DateGroup) -> (Int, Int) {
        switch g {
        case .today: (0, 0)
        case .yesterday: (1, 0)
        case .previous7Days: (2, 0)
        case .previous30Days: (3, 0)
        case .month(let y, let m): (4, -(y * 12 + m))
        case .year(let y): (5, -y)
        case .unknown: (6, 0)
        }
    }

    /// `.none` → `[]` (UI coi là không nhóm). Giữ thứ tự đầu vào trong mỗi nhóm, bỏ nhóm rỗng.
    public static func group(_ items: [FileItem], by: GroupBy, now: Date = Date(),
                             calendar: Calendar = .current) -> [FileGroup] {
        switch by {
        case .none:
            return []
        case .kind:
            var buckets: [KindGroup: [FileItem]] = [:]
            for item in items { buckets[kindGroup(item), default: []].append(item) }
            return KindGroup.allCases.compactMap { k in
                buckets[k].map { FileGroup(key: .kind(k), items: $0) }
            }
        case .modified:
            var buckets: [DateGroup: [FileItem]] = [:]
            for item in items { buckets[dateGroup(item.modified, now: now, calendar: calendar), default: []].append(item) }
            return buckets.keys.sorted { rank($0) < rank($1) }.map { FileGroup(key: .date($0), items: buckets[$0]!) }
        }
    }
}
