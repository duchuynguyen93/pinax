import Testing
import Foundation
import UniformTypeIdentifiers
@testable import PinaxCore

@Suite struct FileGroupingTests {
    static var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }
    /// 2026-11-12 15:00 UTC.
    static let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 15))!

    static func file(_ name: String, modified: Date? = nil) -> FileItem {
        let ext = (name as NSString).pathExtension
        return FileItem(url: URL(fileURLWithPath: "/t/\(name)"), name: name, isDirectory: false, modified: modified,
                        contentType: FileItem.contentType(isDirectory: false, isPackage: false, ext: ext))
    }

    @Test func kinds() {
        let folder = FileItem(url: URL(fileURLWithPath: "/t/d"), name: "d", isDirectory: true, contentType: .folder)
        let app = FileItem(url: URL(fileURLWithPath: "/t/A.app"), name: "A.app", isDirectory: true, isPackage: true,
                           contentType: FileItem.contentType(isDirectory: true, isPackage: true, ext: "app"))
        #expect(FileGrouping.kindGroup(folder) == .folder)
        #expect(FileGrouping.kindGroup(app) == .application)
        let expected: [(String, KindGroup)] = [
            ("a.pdf", .pdf), ("a.png", .image), ("a.svg", .image), ("a.mov", .movie), ("a.mp3", .music), ("a.zip", .archive),
            ("a.dmg", .diskImage), ("a.swift", .sourceCode), ("a.json", .sourceCode), ("a.txt", .document),
            ("a.docx", .document), ("a.xlsx", .spreadsheet), ("a.pptx", .presentation), ("a.key", .presentation),
            ("noext", .other),
        ]
        for (name, kind) in expected { #expect(FileGrouping.kindGroup(Self.file(name)) == kind, "\(name)") }
        let nilType = FileItem(url: URL(fileURLWithPath: "/t/x"), name: "x", isDirectory: false)
        #expect(FileGrouping.kindGroup(nilType) == .other)
    }

    @Test func dateBoundaries() {
        let c = Self.cal, now = Self.now
        let start = c.startOfDay(for: now)
        func d(_ days: Int, _ sec: TimeInterval = 0) -> Date {
            c.date(byAdding: .day, value: -days, to: start)!.addingTimeInterval(sec)
        }
        func g(_ date: Date?) -> DateGroup { FileGrouping.dateGroup(date, now: now, calendar: c) }
        #expect(g(start) == .today)
        #expect(g(now.addingTimeInterval(86400 * 3)) == .today)
        #expect(g(d(0, -1)) == .yesterday)
        #expect(g(d(1)) == .yesterday)
        #expect(g(d(1, -1)) == .previous7Days)
        #expect(g(d(7)) == .previous7Days)
        #expect(g(d(7, -1)) == .previous30Days)
        #expect(g(d(30)) == .previous30Days)
        #expect(g(d(30, -1)) == .month(year: 2026, month: 10))
        #expect(g(c.date(from: DateComponents(year: 2026, month: 2, day: 3))) == .month(year: 2026, month: 2))
        #expect(g(c.date(from: DateComponents(year: 2025, month: 12, day: 31))) == .year(2025))
        #expect(g(nil) == .unknown)
    }

    @Test func groupOrderAndStability() {
        let c = Self.cal, now = Self.now
        let ds: [Date?] = [
            nil,
            c.date(from: DateComponents(year: 2024, month: 5, day: 1)),
            c.date(from: DateComponents(year: 2025, month: 5, day: 1)),
            c.date(from: DateComponents(year: 2026, month: 3, day: 1)),
            c.date(from: DateComponents(year: 2026, month: 9, day: 1)),
            now, now.addingTimeInterval(-86400),
        ]
        let items = ds.enumerated().map { Self.file("f\($0.offset)", modified: $0.element) }
        let groups = FileGrouping.group(items, by: .modified, now: now, calendar: c)
        #expect(groups.map(\.key) == [
            .date(.today), .date(.yesterday), .date(.month(year: 2026, month: 9)), .date(.month(year: 2026, month: 3)),
            .date(.year(2025)), .date(.year(2024)), .date(.unknown),
        ])
        // Giữ thứ tự đầu vào trong nhóm; bỏ nhóm rỗng.
        let kinds = FileGrouping.group(
            [Self.file("b.txt"), Self.file("a.png"), Self.file("a.txt"), Self.file("c.png")], by: .kind)
        #expect(kinds.map(\.key) == [.kind(.document), .kind(.image)])
        #expect(kinds[0].items.map(\.name) == ["b.txt", "a.txt"])
        #expect(kinds[1].items.map(\.name) == ["a.png", "c.png"])
    }

    @Test func noneIsEmpty() {
        #expect(FileGrouping.group([Self.file("a.txt")], by: .none).isEmpty)
    }
}
