import Testing
import Foundation
@testable import PinaxCore

@Suite struct ExecutorTests {
    let box: Sandbox
    let fm = FileManager.default

    init() throws { box = try Sandbox() }

    private func fakeTrash() -> TempTrasher { TempTrasher(dir: box.trash) }

    @Test func performTrashesAndJournals() throws {
        let a = try box.write("a.dmg"), b = try box.write("b.zip")
        let ex = box.executor()
        let r = ex.perform(candidates: [box.candidate(a), box.candidate(b)], title: "Clean",
                           trasher: fakeTrash(), home: box.home)
        #expect(r.outcomes.map(\.status) == [.done, .done])
        #expect(!fm.fileExists(atPath: a.path) && !fm.fileExists(atPath: b.path))
        #expect(try fm.contentsOfDirectory(atPath: box.trash.path).count == 2)
        #expect(r.batch?.ops.count == 2)
        #expect(ex.store.batches.count == 1)
        #expect(fm.fileExists(atPath: box.journalURL.path))
        #expect(r.journalError == nil)
    }

    @Test func undoRestoresFiles() throws {
        let a = try box.write("a.dmg")
        let ex = box.executor()
        let r = ex.perform(candidates: [box.candidate(a)], title: "Clean", trasher: fakeTrash(), home: box.home)
        let out = ex.undo(batch: r.batch!)
        #expect(out.map(\.status) == [.done])
        #expect(fm.fileExists(atPath: a.path))
        #expect(try fm.contentsOfDirectory(atPath: box.trash.path).isEmpty)
        #expect(ex.store.batches[0].undone)
        #expect(ex.store.latestUndoable == nil)
    }

    @Test func undoSkipsWhenOriginalOccupied() throws {
        let a = try box.write("a.dmg")
        let ex = box.executor()
        let r = ex.perform(candidates: [box.candidate(a)], title: "Clean", trasher: fakeTrash(), home: box.home)
        try Data("new".utf8).write(to: a)
        let out = ex.undo(batch: r.batch!)
        #expect(out.map(\.status) == [.skipped(.originalOccupied)])
        #expect(try String(contentsOf: a, encoding: .utf8) == "new") // không bị ghi đè
        #expect(try fm.contentsOfDirectory(atPath: box.trash.path).count == 1)
    }

    @Test func undoSkipsWhenTrashedItemGone() throws {
        let a = try box.write("a.dmg")
        let ex = box.executor()
        let r = ex.perform(candidates: [box.candidate(a)], title: "Clean", trasher: fakeTrash(), home: box.home)
        // Giả lập người dùng đã dọn Thùng rác (di chuyển đi, không xoá).
        let moved = box.root.appendingPathComponent("gone")
        try fm.moveItem(at: box.trash.appendingPathComponent(try fm.contentsOfDirectory(atPath: box.trash.path)[0]), to: moved)
        #expect(ex.undo(batch: r.batch!).map(\.status) == [.skipped(.missing)])
    }

    @Test func performSkipsChangedFingerprint() throws {
        let a = try box.write("a.dmg", bytes: 100)
        let c = box.candidate(a)
        try Data(repeating: 1, count: 500).write(to: a) // đổi size sau khi quét
        let ex = box.executor()
        let r = ex.perform(candidates: [c], title: "Clean", trasher: fakeTrash(), home: box.home)
        #expect(r.outcomes.map(\.status) == [.skipped(.changedSinceScan)])
        #expect(fm.fileExists(atPath: a.path))
        #expect(r.batch == nil)
        #expect(ex.store.batches.isEmpty)
    }

    @Test func performSkipsChangedModificationDate() throws {
        let a = try box.write("a.dmg")
        let c = box.candidate(a)
        try fm.setAttributes([.modificationDate: Date().addingTimeInterval(-9999)], ofItemAtPath: a.path)
        let r = box.executor().perform(candidates: [c], title: "t", trasher: fakeTrash(), home: box.home)
        #expect(r.outcomes.map(\.status) == [.skipped(.changedSinceScan)])
    }

    @Test func performSkipsMissingProtectedAndSymlink() throws {
        let a = try box.write("a.dmg")
        let c = box.candidate(a)
        try fm.moveItem(at: a, to: box.root.appendingPathComponent("elsewhere"))
        let protectedURL = box.home.appendingPathComponent("Documents")
        try fm.createDirectory(at: protectedURL, withIntermediateDirectories: true)
        let protectedCand = box.candidate(protectedURL)
        let target = try box.write("t.bin")
        let link = box.downloads.appendingPathComponent("link")
        try fm.createSymbolicLink(at: link, withDestinationURL: target)
        let linkCand = Candidate(url: link, size: 0, fingerprint: .init(size: 0, modified: Date()),
                                 reason: "", lastUsed: nil, preselected: true)
        let r = box.executor().perform(candidates: [c, protectedCand, linkCand], title: "t",
                                       trasher: fakeTrash(), home: box.home)
        #expect(r.outcomes.map(\.status) == [.skipped(.missing), .skipped(.protectedPath), .skipped(.symlink)])
        #expect(fm.fileExists(atPath: protectedURL.path) && fm.fileExists(atPath: target.path))
    }

    @Test func oneFailureDoesNotBreakBatch() throws {
        struct Flaky: Trasher {
            let inner: TempTrasher
            func trash(_ url: URL) throws -> URL {
                if url.lastPathComponent == "bad.dmg" { throw CocoaError(.fileWriteNoPermission) }
                return try inner.trash(url)
            }
        }
        let bad = try box.write("bad.dmg"), good = try box.write("good.dmg")
        let r = box.executor().perform(candidates: [box.candidate(bad), box.candidate(good)], title: "t",
                                       trasher: Flaky(inner: fakeTrash()), home: box.home)
        guard case .failed = r.outcomes[0].status else { Issue.record("expected failed"); return }
        #expect(r.outcomes[1].status == .done)
        #expect(r.batch?.ops.count == 1)
        #expect(fm.fileExists(atPath: bad.path))
    }

    @Test func journalReloadsFromDiskInFreshStore() throws {
        let a = try box.write("a.dmg")
        let r = box.executor().perform(candidates: [box.candidate(a)], title: "Persist",
                                       trasher: fakeTrash(), home: box.home)
        let fresh = JournalStore(url: box.journalURL)
        #expect(fresh.batches.count == 1)
        #expect(fresh.batches[0].id == r.batch!.id)
        #expect(fresh.batches[0].title == "Persist")
        #expect(fresh.batches[0].ops == r.batch!.ops)
        // Hoàn tác bằng store mới vẫn chạy được.
        let out = Executor(store: fresh, applicationsRoot: box.apps).undo(batch: fresh.batches[0])
        #expect(out.map(\.status) == [.done])
        #expect(JournalStore(url: box.journalURL).batches[0].undone)
    }

    @Test func journalKeepsLast50() throws {
        let store = JournalStore(url: box.journalURL)
        for i in 0..<60 { try store.append(Batch(title: "b\(i)", ops: [])) }
        #expect(store.batches.count == 50)
        #expect(store.batches.first?.title == "b10")
        #expect(JournalStore(url: box.journalURL).batches.count == 50)
    }

    @Test func tidyMoveAndCreateDirUndo() throws {
        let f = try box.write("x.pdf")
        let dir = box.downloads.appendingPathComponent("Documents")
        let dest = dir.appendingPathComponent("x.pdf")
        let ex = box.executor()
        let r = ex.perform(moves: [(from: f, to: dest)], createDirs: [dir], title: "Tidy", home: box.home)
        #expect(r.outcomes.map(\.status) == [.done, .done])
        #expect(fm.fileExists(atPath: dest.path) && !fm.fileExists(atPath: f.path))
        #expect(r.batch?.ops == [.createDir(dir), .move(from: f, to: dest)])
        let out = ex.undo(batch: r.batch!)
        #expect(out.map(\.status) == [.done, .done])
        #expect(fm.fileExists(atPath: f.path))
        #expect(!fm.fileExists(atPath: dir.path)) // thư mục rỗng do Pinax tạo bị gỡ
    }

    @Test func tidyUndoKeepsNonEmptyDir() throws {
        let f = try box.write("x.pdf")
        let dir = box.downloads.appendingPathComponent("Documents")
        let ex = box.executor()
        let r = ex.perform(moves: [(from: f, to: dir.appendingPathComponent("x.pdf"))], createDirs: [dir],
                           title: "Tidy", home: box.home)
        let stranger = try box.write("keep.txt", in: dir) // người dùng thêm file vào
        let out = ex.undo(batch: r.batch!)
        #expect(out.map(\.status) == [.done, .skipped(.directoryNotEmpty)])
        #expect(fm.fileExists(atPath: stranger.path))
        #expect(fm.fileExists(atPath: dir.path))
    }

    @Test func tidyNeverOverwritesAndIgnoresExistingDirs() throws {
        let dir = box.downloads.appendingPathComponent("Documents")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let existing = try box.write("x.pdf", in: dir, bytes: 5)
        let f = try box.write("x.pdf", bytes: 9)
        let r = box.executor().perform(moves: [(from: f, to: existing)], createDirs: [dir], title: "Tidy", home: box.home)
        #expect(r.outcomes.map(\.status) == [.skipped(.destinationExists)]) // dir có sẵn: không báo, không ghi op
        #expect(r.batch == nil)
        #expect(try Data(contentsOf: existing).count == 5)
        #expect(fm.fileExists(atPath: f.path))
    }
}
