import Testing
import Foundation
@testable import PinaxCore

@Suite struct FileOpsTests {
    let box: Sandbox
    let store: JournalStore
    let ops: FileOps
    let trasher: TempTrasher

    init() throws {
        box = try Sandbox()
        store = JournalStore(url: box.journalURL)
        trasher = TempTrasher(dir: box.trash)
        ops = FileOps(executor: box.executor(journal: store), home: box.home, trasher: trasher)
    }

    private func exists(_ u: URL) -> Bool { FileManager.default.fileExists(atPath: u.path) }

    // MARK: rename

    @Test func renameJournalsMoveAndUndoes() throws {
        let f = try box.write("a.txt")
        let r = try ops.rename(f, to: "  b.txt ")
        let dest = box.downloads.appendingPathComponent("b.txt")
        #expect(r.outcomes.first?.status == .done)
        #expect(exists(dest) && !exists(f))
        #expect(r.batch?.ops == [.move(from: f, to: dest)])
        #expect(store.batches.count == 1)

        ops.executor.undo(batch: r.batch!)
        #expect(exists(f) && !exists(dest))
    }

    @Test func renameNeverOverwrites() throws {
        let a = try box.write("a.txt")
        let b = try box.write("b.txt")
        let r = try ops.rename(a, to: "b.txt")
        #expect(r.outcomes.first?.status == .skipped(.destinationExists))
        #expect(r.batch == nil)
        #expect(exists(a) && exists(b))
        // Khác hoa/thường nhưng vẫn là file khác → cũng không ghi đè.
        let c = try box.write("c.txt")
        let r2 = try ops.rename(c, to: "B.TXT")
        #expect(r2.outcomes.first?.status == .skipped(.destinationExists))
        #expect(exists(c))
    }

    @Test func renameCaseOnly() throws {
        let f = try box.write("note.txt")
        let r = try ops.rename(f, to: "Note.txt")
        #expect(r.outcomes.first?.status == .done)
        let names = try FileManager.default.contentsOfDirectory(atPath: box.downloads.path)
        #expect(names.contains("Note.txt") && !names.contains("note.txt"))
    }

    @Test func renameRejectsInvalidNames() throws {
        let f = try box.write("a.txt")
        #expect(throws: FileNameError.empty) { try ops.rename(f, to: "   ") }
        #expect(throws: FileNameError.containsSeparator) { try ops.rename(f, to: "x/y") }
        #expect(throws: FileNameError.containsSeparator) { try ops.rename(f, to: "x:y") }
        #expect(throws: FileNameError.reserved) { try ops.rename(f, to: ".") }
        #expect(throws: FileNameError.reserved) { try ops.rename(f, to: " .. ") }
        #expect(throws: FileNameError.tooLong) { try ops.rename(f, to: String(repeating: "a", count: 300)) }
        #expect(throws: FileNameError.unchanged) { try ops.rename(f, to: "a.txt") }
        #expect(exists(f))
        #expect(store.batches.isEmpty)
    }

    @Test func renameChecksPathGuardOnSourceAndDestination() throws {
        // Nguồn bị cấm: thư mục Downloads.
        let r = try ops.rename(box.downloads, to: "Elsewhere")
        #expect(r.outcomes.first?.status == .skipped(.protectedPath))
        #expect(exists(box.downloads))
        // Đích bị cấm: tên mới trùng thư mục chuẩn `Documents` ở home.
        let f = try box.write("x.txt", in: box.home)
        let r2 = try ops.rename(f, to: "Documents")
        #expect(r2.outcomes.first?.status == .skipped(.protectedPath))
        #expect(exists(f))
    }

    @Test func renameInsideExternalVolumeAllowedButNotVolumeRoot() throws {
        let volumes = box.root.appendingPathComponent("Volumes")
        let ext = volumes.appendingPathComponent("Ext")
        try FileManager.default.createDirectory(at: ext, withIntermediateDirectories: true)
        let f = ext.appendingPathComponent("a.txt")
        try Data([1]).write(to: f)
        let exec = Executor(store: store, applicationsRoot: box.apps, volumesRoot: volumes,
                            isExternalVolume: { $0.lastPathComponent == "Ext" })
        let o = FileOps(executor: exec, home: box.home, trasher: trasher)
        #expect(try o.rename(f, to: "b.txt").outcomes.first?.status == .done)
        #expect(try o.rename(ext, to: "Renamed").outcomes.first?.status == .skipped(.protectedPath))
        #expect(exists(ext))
    }

    // MARK: new folder

    @Test func newFolderNamesAndUndo() throws {
        let r1 = ops.newFolder(in: box.downloads)
        let first = box.downloads.appendingPathComponent("untitled folder")
        #expect(r1.outcomes.first?.url == first)
        #expect(r1.batch?.ops == [.createDir(first)])
        #expect(exists(first))

        let r2 = ops.newFolder(in: box.downloads)
        #expect(r2.outcomes.first?.url.lastPathComponent == "untitled folder 2")
        // Trùng không phân biệt hoa/thường.
        try FileManager.default.createDirectory(at: box.downloads.appendingPathComponent("Untitled Folder 3"), withIntermediateDirectories: false)
        let r3 = ops.newFolder(in: box.downloads)
        #expect(r3.outcomes.first?.url.lastPathComponent == "untitled folder 4")

        ops.executor.undo(batch: r2.batch!)
        #expect(!exists(box.downloads.appendingPathComponent("untitled folder 2")))
        #expect(exists(first))
    }

    @Test func newFolderDeniedInProtectedLocation() {
        let r = ops.newFolder(in: URL(fileURLWithPath: "/usr"))
        #expect(r.batch == nil)
        #expect(r.outcomes.first?.status == .skipped(.protectedPath))
        #expect(!exists(URL(fileURLWithPath: "/usr/untitled folder")))
    }

    @Test func canModifyMirrorsPathGuard() throws {
        let f = try box.write("a.txt")
        #expect(ops.canModify(f))
        #expect(ops.canCreateFolder(in: box.downloads))
        #expect(!ops.canModify(URL(fileURLWithPath: "/System/Library")))
        #expect(!ops.canCreateFolder(in: URL(fileURLWithPath: "/usr")))
        #expect(!ops.canModify(box.home))
    }

    // MARK: trash

    @Test func trashJournalsAndUndoes() throws {
        let a = try box.write("a.txt")
        let d = try box.write("sub/inner.txt").deletingLastPathComponent()
        let gone = box.downloads.appendingPathComponent("gone.txt")
        let r = ops.trash(items: [a, d, gone])
        #expect(r.outcomes.count == 3)
        #expect(r.outcomes.contains { $0.url == gone && $0.status == .skipped(.missing) })
        #expect(r.outcomes.filter { $0.status == .done }.count == 2)
        #expect(!exists(a) && !exists(d))
        #expect(store.batches.count == 1)

        ops.executor.undo(batch: r.batch!)
        #expect(exists(a) && exists(d.appendingPathComponent("inner.txt")))
    }

    @Test func trashSkipsProtectedAndSymlink() throws {
        let target = try box.write("t.txt")
        let link = box.downloads.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let r = ops.trash(items: [box.downloads, link])
        #expect(r.outcomes.contains { $0.url == box.downloads && $0.status == .skipped(.protectedPath) })
        #expect(r.outcomes.contains { $0.url == link && $0.status == .skipped(.symlink) })
        #expect(exists(target))
    }

    @Test func fullFlowNewFolderRenameTrashThenUndoAll() throws {
        let n = ops.newFolder(in: box.downloads)
        let folder = n.outcomes[0].url
        let rn = try ops.rename(folder, to: "Projects")
        let renamed = box.downloads.appendingPathComponent("Projects")
        let tr = ops.trash(items: [renamed])
        #expect(!exists(renamed))
        for b in [tr.batch!, rn.batch!, n.batch!] { ops.executor.undo(batch: b) }
        let left = try FileManager.default.contentsOfDirectory(atPath: box.downloads.path)
        #expect(left.isEmpty)
    }
}
