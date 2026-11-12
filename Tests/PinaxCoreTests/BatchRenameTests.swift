import Testing
import Foundation
@testable import PinaxCore

@Suite struct BatchRenameTests {
    let box: Sandbox
    let store: JournalStore
    let ops: FileOps

    init() throws {
        box = try Sandbox()
        store = JournalStore(url: box.journalURL)
        ops = FileOps(executor: box.executor(journal: store), home: box.home,
                      trasher: TempTrasher(dir: box.trash))
    }

    private func url(_ n: String) -> URL { URL(fileURLWithPath: "/x/\(n)") }
    private func name(_ n: String, _ rule: RenameRule, i: Int = 0, pkg: Bool = false, dir: Bool = false) -> String {
        BatchRename.newName(for: url(n), index: i, count: 3, rule: rule, isPackage: pkg, isDirectory: dir)
    }
    private func read(_ u: URL) -> String? { try? String(contentsOf: u, encoding: .utf8) }
    private func put(_ n: String, _ text: String) throws -> URL {
        let u = box.downloads.appendingPathComponent(n)
        try text.write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    // MARK: Rule

    @Test func replaceKeepsExtensionByDefault() {
        let r = RenameRule.replace(find: "jpg", with: "X", caseSensitive: false, includeExtension: false)
        #expect(name("jpg photo.jpg", r) == "X photo.jpg")
        let r2 = RenameRule.replace(find: "jpg", with: "png", caseSensitive: false, includeExtension: true)
        #expect(name("a.JPG", r2) == "a.png")
    }

    @Test func replaceCaseSensitivity() {
        let ci = RenameRule.replace(find: "ab", with: "-", caseSensitive: false, includeExtension: false)
        let cs = RenameRule.replace(find: "ab", with: "-", caseSensitive: true, includeExtension: false)
        #expect(name("AbabAB.txt", ci) == "---.txt")
        #expect(name("AbabAB.txt", cs) == "Ab-AB.txt")
    }

    @Test func replaceEmptyFindIsNoOp() {
        let r = RenameRule.replace(find: "", with: "x", caseSensitive: false, includeExtension: false)
        #expect(name("a.txt", r) == "a.txt")
    }

    @Test func addText() {
        #expect(name("a.txt", .add(text: "X", atEnd: false)) == "Xa.txt")
        #expect(name("a.txt", .add(text: "X", atEnd: true)) == "aX.txt")
        #expect(name("README", .add(text: "_1", atEnd: true)) == "README_1")
    }

    @Test func dotfileHasNoExtension() {
        #expect(name(".bashrc", .add(text: "2", atEnd: true)) == ".bashrc2")
        #expect(name("archive.tar.gz", .add(text: "2", atEnd: true)) == "archive.tar2.gz")
    }

    @Test func packageKeepsExtensionButPlainFolderDoesNot() {
        let r = RenameRule.add(text: "2", atEnd: true)
        #expect(name("My.app", r, pkg: true, dir: true) == "My2.app")
        #expect(name("v1.2 notes", r, dir: true) == "v1.2 notes2")
        #expect(name("v1.2", r, dir: true) == "v1.22")
    }

    @Test func format() {
        let r = RenameRule.format(base: "Photo", start: 1, digits: 3, numberFirst: false, separator: " ")
        #expect(name("a.jpg", r, i: 0) == "Photo 001.jpg")
        #expect(name("b.jpg", r, i: 11) == "Photo 012.jpg")
        let nf = RenameRule.format(base: "Photo", start: 5, digits: 0, numberFirst: true, separator: "_")
        #expect(name("a.jpg", nf, i: 2) == "7_Photo.jpg")
        #expect(name("Dir.x", nf, i: 0, dir: true) == "5_Photo")
        #expect(name("My.app", nf, i: 0, pkg: true, dir: true) == "5_Photo.app")
        let empty = RenameRule.format(base: "", start: 1, digits: 2, numberFirst: false, separator: "-")
        #expect(name("a.jpg", empty, i: 0) == "01.jpg")
    }

    @Test func changeCase() {
        #expect(name("Hello World.TXT", .changeCase(.lower, includeExtension: false)) == "hello world.TXT")
        #expect(name("Hello World.txt", .changeCase(.upper, includeExtension: false)) == "HELLO WORLD.txt")
        #expect(name("Hello World.txt", .changeCase(.upper, includeExtension: true)) == "HELLO WORLD.TXT")
        #expect(name("hELLO wORLD-foo_bar.txt", .changeCase(.title, includeExtension: false)) == "Hello World-Foo_Bar.txt")
        #expect(name("report v2.final", .changeCase(.title, includeExtension: true)) == "Report V2.final")
    }

    // MARK: Plan

    @Test func unchangedAndInvalid() throws {
        let a = try box.write("a.txt")
        let same = BatchRename.plan([a], rule: .add(text: "", atEnd: true))
        #expect(same[0].issue == .unchanged)
        #expect(!BatchRename.canApply(same))

        let slash = BatchRename.plan([a], rule: .add(text: "/", atEnd: true))
        #expect(slash[0].issue == .invalid(.containsSeparator))
        let empty = BatchRename.plan([try box.write(".x")], rule: .replace(find: ".x", with: "", caseSensitive: true, includeExtension: true))
        #expect(empty[0].issue == .invalid(.empty))
        #expect(!BatchRename.canApply(slash + same))
    }

    @Test func unicodeNormalizationIsUnchanged() throws {
        let nfd = "e\u{301}.txt"   // é dạng NFD
        let a = try box.write(nfd)
        let rule = RenameRule.replace(find: "zzz", with: "y", caseSensitive: true, includeExtension: false)
        #expect(BatchRename.plan([a], rule: rule)[0].issue == .unchanged)
        // Thay bằng chữ NFC cùng nghĩa → vẫn unchanged.
        let r2 = RenameRule.replace(find: "e\u{301}", with: "\u{e9}", caseSensitive: true, includeExtension: false)
        #expect(BatchRename.plan([a], rule: r2)[0].issue == .unchanged)
        // Tìm theo NFC thấy tên NFD.
        let r3 = RenameRule.replace(find: "\u{e9}", with: "E", caseSensitive: true, includeExtension: false)
        let p = BatchRename.plan([a], rule: r3)
        #expect(p[0].newName == "E.txt" && p[0].issue == nil)
    }

    @Test func duplicateDetectedCaseInsensitively() throws {
        let a = try box.write("aa.txt")
        let b = try box.write("bb.txt")
        let ra = BatchRename.plan([a, b], rule: .replace(find: "a", with: "b", caseSensitive: true, includeExtension: false))
        // aa→bb trùng với b (đang đứng yên, unchanged) → b không đổi, a báo duplicate.
        #expect(ra[0].newName == "bb.txt")
        #expect(ra[0].issue == .duplicateInBatch)
        #expect(ra[1].issue == .unchanged)
        // Khác hoa/thường vẫn trùng.
        let c = try box.write("Cc.txt")
        let d = try box.write("dd.txt")
        let rb = BatchRename.plan([c, d], rule: .replace(find: "d", with: "C", caseSensitive: true, includeExtension: false))
        #expect(rb[1].newName == "CC.txt")
        #expect(rb[1].issue == .duplicateInBatch)   // "CC.txt" vs "Cc.txt" (unchanged, giữ chỗ)
    }

    @Test func existsOnDisk() throws {
        let a = try box.write("a.txt")
        _ = try box.write("z.txt")
        let p = BatchRename.plan([a], rule: .replace(find: "a", with: "z", caseSensitive: true, includeExtension: false))
        #expect(p[0].issue == .exists)
        #expect(!BatchRename.canApply(p))
    }

    @Test func targetThatIsAlsoAMovingSourceIsNotExists() throws {
        let a = try box.write("a1.txt")
        let b = try box.write("a2.txt")
        // a1→a2, a2→a3 (chuỗi): a2 sẽ dời đi nên không phải exists.
        let rule = RenameRule.format(base: "a", start: 2, digits: 0, numberFirst: false, separator: "")
        let p = BatchRename.plan([a, b], rule: rule)
        #expect(p.map(\.newName) == ["a2.txt", "a3.txt"])
        #expect(p.allSatisfy { $0.issue == nil })
        #expect(BatchRename.canApply(p))
    }

    @Test func caseOnlyRenameOfItselfIsNotExists() throws {
        let f = try box.write("note.txt")
        let p = BatchRename.plan([f], rule: .changeCase(.upper, includeExtension: false))
        #expect(p[0].newName == "NOTE.txt")
        #expect(p[0].issue == nil)
        let r = ops.batchRename(p, title: "Rename")
        #expect(r.outcomes.allSatisfy { $0.status == .done })
        let names = try FileManager.default.contentsOfDirectory(atPath: box.downloads.path)
        #expect(names == ["NOTE.txt"])
    }

    @Test func canApplyRequiresAtLeastOneChange() {
        #expect(!BatchRename.canApply([]))
    }

    // MARK: Moves + chạy thật

    @Test func movesWithoutCollisionAreSingleStep() throws {
        let a = try box.write("a.txt"), b = try box.write("b.txt")
        let p = BatchRename.plan([a, b], rule: .add(text: "X", atEnd: true))
        let m = BatchRename.moves(p)
        #expect(m.count == 2)
        #expect(m.map { $0.to.lastPathComponent } == ["aX.txt", "bX.txt"])
    }

    @Test func movesSkipUnchanged() throws {
        let a = try box.write("a.txt")
        let u = RenameEntry(source: a, newName: "a.txt", issue: .unchanged)
        #expect(BatchRename.moves([u]).isEmpty)
    }

    @Test func swapRunsForRealAndUndoes() throws {
        let a = try put("a.txt", "AAA"), b = try put("b.txt", "BBB")
        let entries = [RenameEntry(source: a, newName: "b.txt", issue: nil),
                       RenameEntry(source: b, newName: "a.txt", issue: nil)]
        let moves = BatchRename.moves(entries)
        #expect(moves.count == 4)
        #expect(moves[0].to.lastPathComponent.hasPrefix(".pinax-rename-"))
        let r = ops.batchRename(entries, title: "Rename 2 Items")
        #expect(r.outcomes.allSatisfy { $0.status == .done })
        #expect(r.batch?.ops.count == 4)
        #expect(read(a) == "BBB" && read(b) == "AAA")
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.downloads.path).sorted() == ["a.txt", "b.txt"])

        ops.executor.undo(batch: r.batch!)
        #expect(read(a) == "AAA" && read(b) == "BBB")
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.downloads.path).sorted() == ["a.txt", "b.txt"])
    }

    @Test func chainRunsForRealAndUndoes() throws {
        let a = try put("a", "AAA"), b = try put("b", "BBB")
        let c = box.downloads.appendingPathComponent("c")
        let entries = [RenameEntry(source: a, newName: "b", issue: nil),
                       RenameEntry(source: b, newName: "c", issue: nil)]
        let r = ops.batchRename(entries, title: "Rename 2 Items")
        #expect(r.outcomes.allSatisfy { $0.status == .done })
        #expect(!FileManager.default.fileExists(atPath: a.path))
        #expect(read(b) == "AAA" && read(c) == "BBB")

        ops.executor.undo(batch: r.batch!)
        #expect(read(a) == "AAA" && read(b) == "BBB")
        #expect(!FileManager.default.fileExists(atPath: c.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.downloads.path).sorted() == ["a", "b"])
    }

    @Test func formatBatchEndToEnd() throws {
        let urls = try ["x.jpg", "y.jpg", "z.png"].map { try put($0, $0) }
        let p = BatchRename.plan(urls, rule: .format(base: "Photo", start: 1, digits: 2, numberFirst: false, separator: " "))
        #expect(BatchRename.canApply(p))
        let r = ops.batchRename(p, title: "Rename 3 Items")
        #expect(r.outcomes.allSatisfy { $0.status == .done })
        #expect(try FileManager.default.contentsOfDirectory(atPath: box.downloads.path).sorted()
                == ["Photo 01.jpg", "Photo 02.jpg", "Photo 03.png"])
        #expect(store.batches.count == 1)
    }

    @Test func tempNameStaysUnder255Bytes() {
        let long = String(repeating: "á", count: 120) + ".txt"   // 244 byte
        #expect(BatchRename.tempName(hex: "abcd1234", old: long).utf8.count <= 255)
        #expect(BatchRename.tempName(hex: "abcd1234", old: "a.txt") == ".pinax-rename-abcd1234-a.txt")
    }
}
