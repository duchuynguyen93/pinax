import Foundation
import Testing
@testable import PinaxCore

/// Thư mục tạm cho test quét; dọn (kể cả chmod 000) khi deinit.
private final class SpaceTmp {
    let url: URL
    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinax-space-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    deinit {
        chmodAll(url)
        try? FileManager.default.removeItem(at: url)
    }
    private func chmodAll(_ dir: URL) {
        chmod(dir.path, 0o755)
        for c in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] {
            var st = stat()
            let p = dir.appendingPathComponent(c)
            if lstat(p.path, &st) == 0, (st.st_mode & S_IFMT) == S_IFDIR { chmodAll(p) }
        }
    }
    @discardableResult
    func file(_ rel: String, bytes: Int) throws -> URL {
        let u = url.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: u)
        return u
    }
    func dir(_ rel: String) throws {
        try FileManager.default.createDirectory(at: url.appendingPathComponent(rel), withIntermediateDirectories: true)
    }
}

private func allocated(_ url: URL) -> Int64 {
    var st = stat()
    guard lstat(url.path, &st) == 0 else { return 0 }
    return Int64(st.st_blocks) * 512
}

private func child(_ n: SizeNode, _ name: String) -> SizeNode? { n.children.first { $0.name == name } }

private func checkTotals(_ n: SizeNode) {
    if n.children.isEmpty { return }
    if n.kind == .directory {
        let own = n.size - n.children.reduce(0) { $0 + $1.size }
        #expect(own >= 0)
        #expect(n.fileCount == n.children.reduce(0) { $0 + $1.fileCount })
    }
    for c in n.children {
        #expect(c.parent === n)
        checkTotals(c)
    }
}

@Suite struct SpaceScannerTests {
    private func scanner(skip: Set<String> = [], min: Int64 = 1_048_576) -> SpaceScanner {
        SpaceScanner(options: .init(minFileBytes: min, skipPaths: skip))
    }

    @Test func totalsMatchTree() throws {
        let t = try SpaceTmp()
        let big = try t.file("a/big.bin", bytes: 2_000_000)
        try t.file("a/b/big2.bin", bytes: 3_000_000)
        try t.file("small.txt", bytes: 4096)
        let r = try scanner().scan(root: t.url)
        let a = try #require(child(r.root, "a"))
        #expect(a.kind == .directory)
        let bigNode = try #require(child(a, "big.bin"))
        #expect(bigNode.size == allocated(big))
        #expect(bigNode.kind == .file)
        checkTotals(r.root)
        let expected = allocated(t.url) + allocated(t.url.appendingPathComponent("a"))
            + allocated(t.url.appendingPathComponent("a/b")) + allocated(big)
            + allocated(t.url.appendingPathComponent("a/b/big2.bin")) + allocated(t.url.appendingPathComponent("small.txt"))
        #expect(r.root.size == expected)
        #expect(r.root.fileCount == 3)
        #expect(r.root.name == t.url.standardizedFileURL.path)
        #expect(r.unreadableCount == 0)
        #expect(bigNode.url.path == big.path)
        // sắp giảm dần
        for n in [r.root, a] {
            let sizes = n.children.map(\.size)
            #expect(sizes == sizes.sorted(by: >))
        }
    }

    @Test func hardLinkCountedOnce() throws {
        let t = try SpaceTmp()
        let f = try t.file("one.bin", bytes: 2_000_000)
        try FileManager.default.linkItem(at: f, to: t.url.appendingPathComponent("two.bin"))
        let r = try scanner().scan(root: t.url)
        let bigs = r.root.children.filter { $0.kind == .file }
        #expect(bigs.count == 1)
        #expect(r.root.fileCount == 1)
        #expect(r.root.size == allocated(t.url) + allocated(f))
    }

    @Test func symlinkSkipped() throws {
        let t = try SpaceTmp()
        let f = try t.file("real/big.bin", bytes: 2_000_000)
        try FileManager.default.createSymbolicLink(at: t.url.appendingPathComponent("link.bin"), withDestinationURL: f)
        try FileManager.default.createSymbolicLink(at: t.url.appendingPathComponent("linkdir"),
                                                   withDestinationURL: t.url.appendingPathComponent("real"))
        let r = try scanner().scan(root: t.url)
        #expect(child(r.root, "link.bin") == nil)
        #expect(child(r.root, "linkdir") == nil)
        #expect(r.root.fileCount == 1)
        let expected = allocated(t.url) + allocated(t.url.appendingPathComponent("real")) + allocated(f)
        #expect(r.root.size == expected)
    }

    @Test func packageIsLeaf() throws {
        let t = try SpaceTmp()
        let app = "Foo.app"
        try t.file("\(app)/Contents/Info.plist", bytes: 200)
        let exe = try t.file("\(app)/Contents/MacOS/foo", bytes: 2_000_000)
        try t.file("\(app)/Contents/Resources/x.dat", bytes: 4096)
        let r = try scanner().scan(root: t.url)
        let pkg = try #require(child(r.root, app))
        #expect(pkg.kind == .package)
        #expect(pkg.children.isEmpty)
        #expect(pkg.fileCount == 3)
        var expected: Int64 = 0
        for rel in ["", "Contents", "Contents/MacOS", "Contents/Resources"] {
            expected += allocated(t.url.appendingPathComponent(app).appendingPathComponent(rel))
        }
        expected += allocated(exe) + allocated(t.url.appendingPathComponent("\(app)/Contents/Info.plist"))
            + allocated(t.url.appendingPathComponent("\(app)/Contents/Resources/x.dat"))
        #expect(pkg.size == expected)
        #expect(r.root.size == allocated(t.url) + pkg.size)
        #expect(pkg.url.path == t.url.appendingPathComponent(app).path)
    }

    @Test func smallFilesAggregated() throws {
        let t = try SpaceTmp()
        var sum: Int64 = 0
        for i in 0..<5 {
            let u = try t.file("d/s\(i).txt", bytes: 4096)
            sum += allocated(u)
        }
        try t.file("d/big.bin", bytes: 2_000_000)
        let r = try scanner().scan(root: t.url)
        let d = try #require(child(r.root, "d"))
        let others = try #require(d.children.first { $0.kind == .others })
        #expect(others.fileCount == 5)
        #expect(others.size == sum)
        #expect(others.url.path == d.url.path)
        #expect(!others.isTrashable)
        #expect(d.children.filter { $0.kind == .file }.count == 1)
        #expect(d.fileCount == 6)
        // thư mục không có file nhỏ thì không có others
        #expect(r.root.children.allSatisfy { $0.kind != .others })
    }

    @Test func skipPathsNotRead() throws {
        let t = try SpaceTmp()
        try t.file("skipme/huge.bin", bytes: 2_000_000)
        try t.file("keep/big.bin", bytes: 2_000_000)
        let skip = t.url.appendingPathComponent("skipme").standardizedFileURL.path
        let r = try scanner(skip: [skip]).scan(root: t.url)
        let s = try #require(child(r.root, "skipme"))
        #expect(s.skipped)
        #expect(s.size == 0)
        #expect(s.children.isEmpty)
        #expect(s.fileCount == 0)
        #expect(r.root.fileCount == 1)
        let defaults = SpaceScanner.Options.defaults(home: URL(fileURLWithPath: "/Users/x"))
        #expect(defaults.skipPaths == ["/Users/x/Library/Containers", "/Users/x/Library/Group Containers"])
    }

    /// Bất biến: thư mục bị bỏ qua / không đọc được / package nằm giữa cây không làm lệch stack —
    /// mọi anh em phía sau vẫn ở đúng chỗ, tổng của gốc = tổng progress đếm được.
    @Test func skippedAndUnreadableKeepTreeAligned() throws {
        let t = try SpaceTmp()
        for top in ["a", "m", "z"] {
            try t.file("\(top)/Library/Containers/x/big.bin", bytes: 2_000_000)
            try t.file("\(top)/Library/Group Containers/y/big.bin", bytes: 2_000_000)
            try t.file("\(top)/Library/Locked/big.bin", bytes: 2_000_000)
            try t.file("\(top)/Library/Tool.app/Contents/Info.plist", bytes: 100)
            try t.file("\(top)/Library/Tool.app/Contents/big.bin", bytes: 2_000_000)
            for sib in ["b", "k", "x"] { try t.file("\(top)/Library/\(sib)/big.bin", bytes: 2_000_000) }
            try t.file("\(top)/after/big.bin", bytes: 2_000_000)
        }
        var skip: Set<String> = []
        for top in ["a", "m", "z"] {
            let lib = t.url.appendingPathComponent("\(top)/Library")
            skip.insert(lib.appendingPathComponent("Containers").standardizedFileURL.path)
            skip.insert(lib.appendingPathComponent("Group Containers").standardizedFileURL.path)
            chmod(lib.appendingPathComponent("Locked").path, 0o000)
        }
        final class Box: @unchecked Sendable { var last: SpaceScanner.Progress? }
        let box = Box()
        let r = try scanner(skip: skip).scan(root: t.url) { box.last = $0 }
        let last = try #require(box.last)
        #expect(Set(r.root.children.map(\.name)) == ["a", "m", "z"])
        #expect(Set(last.finishedTopLevel.map(\.name)) == ["a", "m", "z"])
        #expect(r.root.size == last.bytes)
        #expect(r.root.fileCount == last.files)
        #expect(r.unreadableCount == 3)
        for top in ["a", "m", "z"] {
            let n = try #require(child(r.root, top))
            #expect(Set(n.children.map(\.name)) == ["Library", "after"])
            let lib = try #require(child(n, "Library"))
            #expect(Set(lib.children.map(\.name)) == ["Containers", "Group Containers", "Locked", "Tool.app", "b", "k", "x"])
            #expect(child(lib, "Containers")?.skipped == true)
            #expect(child(lib, "Locked")?.isUnreadable == true)
            #expect(child(lib, "Tool.app")?.kind == .package)
        }
        checkTotals(r.root)
    }

    @Test func unreadableDirectory() throws {
        let t = try SpaceTmp()
        try t.file("locked/secret.bin", bytes: 2_000_000)
        try t.file("ok/big.bin", bytes: 2_000_000)
        let locked = t.url.appendingPathComponent("locked")
        chmod(locked.path, 0o000)
        defer { chmod(locked.path, 0o755) }
        let r = try scanner().scan(root: t.url)
        let n = try #require(child(r.root, "locked"))
        #expect(n.isUnreadable)
        #expect(n.children.isEmpty)
        #expect(r.unreadableCount == 1)
        #expect(r.root.fileCount == 1)
    }

    @Test func cancellation() async throws {
        let t = try SpaceTmp()
        try t.file("a/big.bin", bytes: 2_000_000)
        let s = scanner()
        let root = t.url
        let task = Task.detached { () throws -> SpaceScanner.Result in
            while !Task.isCancelled { await Task.yield() }
            return try s.scan(root: root)
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func notADirectoryThrows() throws {
        let t = try SpaceTmp()
        let f = try t.file("f.txt", bytes: 10)
        #expect(throws: SpaceScanner.ScanError.self) { try scanner().scan(root: f) }
        #expect(throws: SpaceScanner.ScanError.self) {
            try scanner().scan(root: t.url.appendingPathComponent("missing"))
        }
    }

    @Test func progressReportsFinal() throws {
        let t = try SpaceTmp()
        try t.file("a/big.bin", bytes: 2_000_000)
        try t.file("b/big.bin", bytes: 2_000_000)
        try t.file("top.bin", bytes: 2_000_000)
        final class Box: @unchecked Sendable { var last: SpaceScanner.Progress? }
        let box = Box()
        _ = try scanner().scan(root: t.url) { box.last = $0 }
        let last = try #require(box.last)
        #expect(last.files == 3)
        #expect(Set(last.finishedTopLevel.map(\.name)) == ["a", "b"])
    }

    @Test func removeFromParentUpdatesAncestors() throws {
        let t = try SpaceTmp()
        try t.file("a/b/big.bin", bytes: 2_000_000)
        try t.file("a/other.bin", bytes: 3_000_000)
        let r = try scanner().scan(root: t.url)
        let a = try #require(child(r.root, "a"))
        let b = try #require(child(a, "b"))
        let rootBefore = r.root.size, aBefore = a.size
        let bSize = b.size
        #expect(b.removeFromParent())
        #expect(a.size == aBefore - bSize)
        #expect(r.root.size == rootBefore - bSize)
        #expect(r.root.fileCount == 1 && a.fileCount == 1)
        #expect(b.parent == nil)
        #expect(a.children.contains { $0 === b } == false)
        #expect(!r.root.removeFromParent())
        checkTotals(r.root)
    }

    @Test func replaceSkippedNode() throws {
        let t = try SpaceTmp()
        try t.file("skipme/huge.bin", bytes: 2_000_000)
        try t.file("keep/big.bin", bytes: 3_000_000)
        let skipURL = t.url.appendingPathComponent("skipme")
        let first = try scanner(skip: [skipURL.standardizedFileURL.path]).scan(root: t.url)
        let node = try #require(child(first.root, "skipme"))
        let before = first.root.size
        let sub = try scanner().scan(root: skipURL)
        node.replace(with: sub.root)
        #expect(sub.root.name == "skipme")
        #expect(sub.root.parent === first.root)
        #expect(first.root.size == before + sub.root.size)
        #expect(first.root.fileCount == 2)
        #expect(sub.root.url.path == skipURL.path)
        #expect(first.root.children.contains { $0 === sub.root })
        #expect(!first.root.children.contains { $0 === node })
        let sizes = first.root.children.map(\.size)
        #expect(sizes == sizes.sorted(by: >))
        checkTotals(first.root)
    }
}

@Suite struct SpaceSmokeTests {
    /// Quét home THẬT, chỉ đọc, tuỳ chọn mặc định. Bật bằng PINAX_SMOKE=1.
    @Test func spaceMapRealHome() throws {
        guard ProcessInfo.processInfo.environment["PINAX_SMOKE"] == "1" else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let r = try SpaceScanner(options: .defaults(home: home)).scan(root: home)
        print("=== SPACE MAP SMOKE (read-only)")
        print(String(format: "duration %.1fs, files %d, total %lld bytes (%.1f GB), unreadable %d",
                     r.duration, r.root.fileCount, r.root.size, Double(r.root.size) / 1e9, r.unreadableCount))
        for c in r.root.children.prefix(10) {
            let flags = (c.skipped ? " [skipped]" : "") + (c.isUnreadable ? " [unreadable]" : "")
            print(String(format: "  %8.2f GB  %@%@", Double(c.size) / 1e9, c.name, flags))
        }
    }
}
