import Testing
import Foundation
@testable import PinaxCore

@Suite struct TidyPlannerTests {
    let box: Sandbox
    let fm = FileManager.default
    /// File vừa tạo luôn "cũ" hơn `now` > 60 s.
    let later = Date().addingTimeInterval(3600)

    init() throws { box = try Sandbox() }

    private func plan() -> TidyPlan { TidyPlanner.plan(folder: box.downloads, now: later, home: box.home) }
    private func listing() throws -> [String] { try fm.contentsOfDirectory(atPath: box.downloads.path).sorted() }

    @Test func classifiesEachKind() {
        let cases: [(String, FileKind)] = [
            ("a.dmg", .installers), ("a.pkg", .installers), ("a.zip", .archives), ("a.tar", .archives),
            ("a.png", .images), ("a.heic", .images), ("a.svg", .images), ("a.mp4", .videos), ("a.mov", .videos),
            ("a.mp3", .audio), ("a.wav", .audio), ("a.pdf", .documents), ("a.docx", .documents),
            ("a.csv", .documents), ("a.md", .documents), ("a.json", .code), ("a.swift", .code),
            ("a.py", .code), ("a.ts", .code), ("a.xyz123", .other), ("noext", .other),
        ]
        for (name, kind) in cases {
            #expect(FileKind.classify(URL(fileURLWithPath: "/x/\(name)")) == kind, "\(name)")
        }
        #expect(FileKind.allCases.map(\.folderName) ==
                ["Installers", "Archives", "Images", "Videos", "Audio", "Documents", "Code", "Other"])
    }

    @Test func skipsUnsafeEntries() throws {
        try box.write("a.crdownload")
        let recent = try box.write("recent.pdf")
        try box.write(".hidden.pdf")
        try fm.createDirectory(at: box.downloads.appendingPathComponent("somedir"), withIntermediateDirectories: true)
        try fm.createDirectory(at: box.downloads.appendingPathComponent("Safari.download"), withIntermediateDirectories: true)
        let target = try box.write("target.pdf")
        try fm.setAttributes([.modificationDate: later.addingTimeInterval(-10)], ofItemAtPath: recent.path)
        let link = box.downloads.appendingPathComponent("link.pdf")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)

        let p = plan()
        let reasons = Dictionary(uniqueKeysWithValues: p.skipped.map { ($0.0.lastPathComponent, $0.1) })
        #expect(reasons["a.crdownload"] == .inProgressDownload)
        #expect(reasons["Safari.download"] == .inProgressDownload)
        #expect(reasons["recent.pdf"] == .recentlyModified)
        #expect(reasons[".hidden.pdf"] == .hidden)
        #expect(reasons["somedir"] == .directory)
        #expect(reasons["link.pdf"] == .symlinkOrAlias)
        #expect(p.moves.map { $0.from.lastPathComponent } == ["target.pdf"])
    }

    @Test func categoryFoldersAreNotMoved() throws {
        try fm.createDirectory(at: box.downloads.appendingPathComponent("Documents"), withIntermediateDirectories: true)
        try box.write("a.pdf")
        let p = plan()
        #expect(p.skipped.contains { $0.0.lastPathComponent == "Documents" && $0.1 == .directory })
        #expect(p.createDirs.isEmpty) // Documents đã tồn tại
        #expect(p.moves.count == 1)
    }

    @Test func conflictsWithDiskIncrementUntilFree() throws {
        let docs = box.downloads.appendingPathComponent("Documents")
        try box.write("x.pdf", in: docs)
        try box.write("x 2.pdf", in: docs)
        try box.write("x.pdf")
        try box.write("other.xyz123")
        let p = plan()
        #expect(p.moves.map { $0.to.lastPathComponent }.sorted() == ["other.xyz123", "x 3.pdf"])
        #expect(p.createDirs.map(\.lastPathComponent) == ["Other"])
    }

    /// Đĩa không phân biệt hoa/thường (APFS): "X.PDF" có sẵn ở đích thì "x.pdf" đến phải đổi tên.
    @Test func conflictIsCaseInsensitive() throws {
        let docs = box.downloads.appendingPathComponent("Documents")
        try box.write("X.PDF", in: docs)
        try box.write("x.pdf")
        #expect(plan().moves.map { $0.to.lastPathComponent } == ["x 2.pdf"])
    }

    /// Hai file đến cùng đích sau khi phân loại: tên trùng (không phân biệt hoa/thường) phải được đánh số.
    @Test func conflictsBetweenIncomingFiles() throws {
        // Cùng kind, cùng tên sau lowercase chỉ xảy ra trên ổ case-sensitive; ở đây dùng uniqueName qua plan thật
        // bằng hai file khác tên gốc nhưng đã chiếm "a 2.pdf": a.pdf (có sẵn ở đích) + a.pdf đến + "a 2.pdf" đến.
        let docs = box.downloads.appendingPathComponent("Documents")
        try box.write("a.pdf", in: docs)
        try box.write("a.pdf")
        try box.write("a 2.pdf")
        let names = plan().moves.map { $0.to.lastPathComponent }
        #expect(Set(names).count == names.count)
        #expect(Set(names.map { $0.lowercased() }).count == names.count)
        #expect(names.sorted() == ["a 2.pdf", "a 3.pdf"])
    }

    @Test func noExtensionConflict() throws {
        try box.write("README", in: box.downloads.appendingPathComponent("Other"))
        try box.write("README")
        #expect(plan().moves.map { $0.to.lastPathComponent } == ["README 2"])
    }

    @Test func filteredDropsKindsAndDirs() throws {
        try box.write("a.pdf", bytes: 5000)
        try box.write("b.png")
        let p = plan()
        #expect(p.createDirs.count == 2)
        #expect(p.bytesByKind[.documents] ?? 0 > 0)
        let f = p.filtered(kinds: [.images])
        #expect(f.moves.map { $0.from.lastPathComponent } == ["b.png"])
        #expect(f.createDirs.map(\.lastPathComponent) == ["Images"])
        #expect(f.bytesByKind[.documents] == nil)
        #expect(p.filtered(kinds: []).moves.isEmpty)
    }

    @Test func endToEndTidyAndUndo() throws {
        for n in ["a.pdf", "b.png", "c.zip", "d.dmg", "e.unknownext"] { try box.write(n) }
        let before = try listing()
        let ex = box.executor()
        let p = plan()
        let r = ex.perform(moves: p.moves, createDirs: p.createDirs, title: "Tidy", home: box.home)
        #expect(r.outcomes.allSatisfy { $0.status == .done })
        #expect(r.journalError == nil)
        #expect(fm.fileExists(atPath: box.downloads.appendingPathComponent("Documents/a.pdf").path))
        #expect(fm.fileExists(atPath: box.downloads.appendingPathComponent("Images/b.png").path))
        #expect(fm.fileExists(atPath: box.downloads.appendingPathComponent("Archives/c.zip").path))
        #expect(fm.fileExists(atPath: box.downloads.appendingPathComponent("Installers/d.dmg").path))
        #expect(fm.fileExists(atPath: box.downloads.appendingPathComponent("Other/e.unknownext").path))
        #expect(try listing() != before)

        ex.undo(batch: try #require(r.batch))
        #expect(try listing() == before)
    }
}
