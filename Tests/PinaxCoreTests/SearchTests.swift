import Testing
import Foundation
@testable import PinaxCore

@Suite struct NameMatcherTests {
    @Test func foldStripsCaseAndDiacritics() {
        #expect(NameMatcher.fold("Tài Liệu") == "tai lieu")
        #expect(NameMatcher.fold("Đà") == "da")
        #expect(NameMatcher.fold("đ") == "d")
    }

    @Test func multipleTermsAreAnded() {
        let m = NameMatcher("tai  LIEU")
        #expect(m.terms == ["tai", "lieu"])
        #expect(m.matches("Tài liệu 2024.pdf"))
        #expect(m.matches("liệu - tài.txt"))
        #expect(!m.matches("Tài chính.pdf"))
    }

    @Test func emptyMatchesEverything() {
        for q in ["", "   \t"] {
            let m = NameMatcher(q)
            #expect(m.isEmpty)
            #expect(m.matches("bất kỳ"))
        }
        #expect(!NameMatcher("a").isEmpty)
    }

    @Test func dStrokeMatches() {
        #expect(NameMatcher("duong").matches("Đường đi"))
    }
}

@Suite struct SpotlightPredicateTests {
    @Test func emptyIsNil() {
        #expect(SpotlightPredicate.make("") == nil)
        #expect(SpotlightPredicate.make("  ") == nil)
    }

    @Test func quoteIsValidAndEvaluates() throws {
        let p = try #require(SpotlightPredicate.make("a\"b"))
        #expect(p.evaluate(with: ["kMDItemFSName": "a\"b.txt"]))
        #expect(!p.evaluate(with: ["kMDItemFSName": "ab.txt"]))
    }

    @Test func starIsLiteral() throws {
        let p = try #require(SpotlightPredicate.make("a*b"))
        #expect(p.evaluate(with: ["kMDItemFSName": "xa*b.txt"]))
        #expect(!p.evaluate(with: ["kMDItemFSName": "axxb.txt"]))
        let q = try #require(SpotlightPredicate.make("a?b"))
        #expect(!q.evaluate(with: ["kMDItemFSName": "axb"]))
        #expect(q.evaluate(with: ["kMDItemFSName": "a?b"]))
    }

    /// NSMetadataQuery từ chối NSCompoundPredicate một vế → một từ phải là predicate đơn.
    @Test func singleTermIsNotCompound() throws {
        let p = try #require(SpotlightPredicate.make("readme"))
        #expect(!(p is NSCompoundPredicate))
        #expect(p.evaluate(with: ["kMDItemFSName": "README.md"]))
    }

    @Test func termsAreAnded() throws {
        let p = try #require(SpotlightPredicate.make("foo bar"))
        #expect(p.evaluate(with: ["kMDItemFSName": "BAR foo.txt"]))
        #expect(!p.evaluate(with: ["kMDItemFSName": "foo.txt"]))
    }
}

@Suite struct NameSearchTests {
    let root: URL
    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("pinax-search-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = base.resolvingSymlinksInPath()
    }

    func touch(_ rel: String) throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: url)
    }

    func search(_ q: String, _ opts: NameSearch.Options = .init()) throws -> (names: [String], cut: Bool) {
        let box = Box()
        let cut = try NameSearch(options: opts).run(root: root, matcher: NameMatcher(q)) { urls in
            box.add(urls)
        }
        return (box.urls.map { $0.path.replacingOccurrences(of: root.path + "/", with: "") }.sorted(), cut)
    }

    final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var urls: [URL] = []
        var calls = 0
        func add(_ u: [URL]) { lock.lock(); urls += u; calls += 1; lock.unlock() }
    }

    @Test func findsAtManyLevels() throws {
        try touch("Tài liệu.txt")
        try touch("a/b/c/tai lieu 2.txt")
        try touch("a/other.txt")
        let r = try search("tai lieu")
        #expect(r.names == ["Tài liệu.txt", "a/b/c/tai lieu 2.txt"])
        #expect(!r.cut)
        #expect(try search("").names.count >= 5)
    }

    @Test func hiddenHandling() throws {
        try touch(".secret/note.txt")
        try touch(".note-hidden.txt")
        try touch("vis/note.txt")
        #expect(try search("note").names == ["vis/note.txt"])
        let all = try search("note", .init(includeHidden: true)).names
        #expect(all == [".note-hidden.txt", ".secret/note.txt", "vis/note.txt"])
    }

    @Test func packageNotEnteredButMatchable() throws {
        try touch("Foo.app/Contents/Info.plist")
        try touch("Foo.app/Contents/needle.txt")
        let info = ["CFBundleIdentifier": "x.foo"] as NSDictionary
        try info.write(to: root.appendingPathComponent("Foo.app/Contents/Info.plist"))
        #expect(try search("needle").names.isEmpty)
        #expect(try search("foo").names == ["Foo.app"])
    }

    @Test func symlinkNotFollowed() throws {
        try touch("real/inside-needle.txt")
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("link-dir"), withDestinationURL: root.appendingPathComponent("real"))
        let r = try search("needle").names
        #expect(r == ["real/inside-needle.txt"])
        #expect(try search("link-dir").names == ["link-dir"])
    }

    @Test func limitCuts() throws {
        for i in 0..<20 { try touch("f\(i).txt") }
        let r = try search("f", .init(limit: 5))
        #expect(r.names.count == 5)
        #expect(r.cut)
        let ok = try search("f", .init(limit: 100))
        #expect(!ok.cut)
    }

    @Test func skipPathsNotEntered() throws {
        try touch("Containers/needle.txt")
        try touch("keep/needle.txt")
        let skip = root.appendingPathComponent("Containers").path
        #expect(try search("needle", .init(skipPaths: [skip])).names == ["keep/needle.txt"])
        // thư mục bị bỏ qua không phải kết quả, kể cả khi tên khớp
        #expect(try search("Containers", .init(skipPaths: [skip])).names.isEmpty)
    }

    @Test func cancelThrows() async throws {
        for i in 0..<10 { try touch("d/f\(i).txt") }
        let root = self.root
        let task = Task.detached { () -> Bool in
            while !Task.isCancelled { await Task.yield() }
            return try NameSearch(options: .init()).run(root: root, matcher: NameMatcher("")) { _ in }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func rootNotDirectoryThrows() throws {
        try touch("file.txt")
        #expect(throws: NameSearch.SearchError.self) {
            try NameSearch(options: .init()).run(root: root.appendingPathComponent("file.txt"), matcher: NameMatcher("")) { _ in }
        }
    }

    @Test func neverCallsWithEmptyBatch() throws {
        try touch("x.txt")
        let box = Box()
        _ = try NameSearch(options: .init()).run(root: root, matcher: NameMatcher("zzz")) { box.add($0) }
        #expect(box.calls == 0)
    }
}
