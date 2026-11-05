import Testing
import Foundation
@testable import PinaxCore

@Suite struct TransferTests {
    let box: Sandbox
    let store: JournalStore
    let trasher: TempTrasher
    let dest: URL
    let fm = FileManager.default

    init() throws {
        box = try Sandbox()
        store = JournalStore(url: box.journalURL)
        trasher = TempTrasher(dir: box.trash)
        dest = box.downloads.appendingPathComponent("dest", isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
    }

    private func exists(_ u: URL) -> Bool { Executor.exists(u) }
    private func runner(space: @escaping (URL) -> Int64? = { _ in nil }) -> TransferRunner {
        TransferRunner(executor: box.executor(journal: store), home: box.home, trasher: trasher, availableSpace: space)
    }
    private func run(_ sources: [URL], kind: TransferKind = .copy, policy: ConflictPolicy = .skip,
                     sameVolume: Bool = true, to d: URL? = nil,
                     space: @escaping (URL) -> Int64? = { _ in nil },
                     progress: (TransferProgress) -> Void = { _ in },
                     isCancelled: () -> Bool = { false }) -> PerformResult {
        let plan = TransferPlan.make(sources: sources, destination: d ?? dest, kind: kind, isSameVolume: { _, _ in sameVolume })
        return runner(space: space).run(plan: plan, policy: policy, title: "T", progress: progress, isCancelled: isCancelled)
    }
    private func read(_ u: URL) -> [UInt8]? { fm.contents(atPath: u.path).map { [UInt8]($0) } }
    private func listing() -> [String] { (try? fm.contentsOfDirectory(atPath: dest.path)) ?? [] }
    private func trashContents() -> [String] { (try? fm.contentsOfDirectory(atPath: box.trash.path)) ?? [] }

    // MARK: đặt tên

    @Test func namingNumberedAndCopySuffix() throws {
        let d = box.downloads.appendingPathComponent("names")
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        try box.write("photo.jpg", in: d)
        #expect(TransferNaming.availableName(for: "photo.jpg", in: d, isDirectory: false, style: .numbered) == "photo 2.jpg")
        try box.write("photo 2.jpg", in: d)
        #expect(TransferNaming.availableName(for: "photo.jpg", in: d, isDirectory: false, style: .numbered) == "photo 3.jpg")
        #expect(TransferNaming.availableName(for: "photo.jpg", in: d, isDirectory: false, style: .copySuffix) == "photo copy.jpg")
        try box.write("photo copy.jpg", in: d)
        #expect(TransferNaming.availableName(for: "photo.jpg", in: d, isDirectory: false, style: .copySuffix) == "photo copy 2.jpg")
    }

    @Test func namingExtensionsFoldersPackages() throws {
        let d = box.downloads.appendingPathComponent("names2")
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        try box.write("a.tar.gz", in: d)
        try fm.createDirectory(at: d.appendingPathComponent("Folder.v1"), withIntermediateDirectories: true)
        try fm.createDirectory(at: d.appendingPathComponent("My Folder"), withIntermediateDirectories: true)
        try fm.createDirectory(at: d.appendingPathComponent("X.app"), withIntermediateDirectories: true)
        #expect(TransferNaming.availableName(for: "a.tar.gz", in: d, isDirectory: false, style: .numbered) == "a.tar 2.gz")
        #expect(TransferNaming.availableName(for: "My Folder", in: d, isDirectory: true, style: .numbered) == "My Folder 2")
        #expect(TransferNaming.availableName(for: "My Folder", in: d, isDirectory: true, style: .copySuffix) == "My Folder copy")
        #expect(TransferNaming.availableName(for: "X.app", in: d, isDirectory: true, style: .numbered) == "X 2.app")
    }

    @Test func namingIsCaseInsensitiveAndSeesBrokenSymlinks() throws {
        let d = box.downloads.appendingPathComponent("names3")
        try fm.createDirectory(at: d, withIntermediateDirectories: true)
        try box.write("Photo.JPG", in: d)
        #expect(TransferNaming.availableName(for: "photo.jpg", in: d, isDirectory: false, style: .numbered) == "photo 2.jpg")
        try fm.createSymbolicLink(atPath: d.appendingPathComponent("photo 2.jpg").path, withDestinationPath: "/nonexistent-pinax")
        #expect(TransferNaming.availableName(for: "photo.jpg", in: d, isDirectory: false, style: .numbered) == "photo 3.jpg")
    }

    // MARK: plan

    @Test func planConflictIntoItselfMissingSameParent() throws {
        let a = try box.write("a.txt")
        let folder = box.downloads.appendingPathComponent("F", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try box.write("a.txt", in: dest)
        let missing = box.downloads.appendingPathComponent("ghost.txt")

        let p = TransferPlan.make(sources: [a, missing], destination: dest, kind: .copy)
        #expect(p.items[0].conflict && p.items[0].skip == nil)
        #expect(p.items[1].skip == .missing)
        #expect(p.conflictCount == 1)

        let inner = folder.appendingPathComponent("inner", isDirectory: true)
        try fm.createDirectory(at: inner, withIntermediateDirectories: true)
        #expect(TransferPlan.make(sources: [folder], destination: folder, kind: .copy).items[0].skip == .intoItself)
        #expect(TransferPlan.make(sources: [folder], destination: inner, kind: .move).items[0].skip == .intoItself)
        // "F" không phải tiền tố thật của "F2".
        let f2 = box.downloads.appendingPathComponent("F2", isDirectory: true)
        try fm.createDirectory(at: f2, withIntermediateDirectories: true)
        #expect(TransferPlan.make(sources: [folder], destination: f2, kind: .copy).items[0].skip == nil)

        // Move vào chính thư mục cha: bỏ item.
        #expect(TransferPlan.make(sources: [a], destination: box.downloads, kind: .move).items.isEmpty)
        // Copy vào chính thư mục cha: copySuffix, không conflict.
        let c = TransferPlan.make(sources: [a], destination: box.downloads, kind: .copy).items[0]
        #expect(c.target.lastPathComponent == "a copy.txt" && !c.conflict)
        // Duplicate nhiều lần: tên dành trước, không trùng nhau.
        let dd = TransferPlan.make(sources: [a], destination: box.downloads, kind: .duplicate).items[0]
        #expect(dd.target.lastPathComponent == "a copy.txt")
    }

    // MARK: copy

    @Test func copyFileNestedDirAndSymlink() throws {
        let tree = box.downloads.appendingPathComponent("tree", isDirectory: true)
        try box.write("sub/deep.bin", in: tree, bytes: 5000)
        try box.write("top.txt", in: tree, bytes: 10)
        try fm.createSymbolicLink(atPath: tree.appendingPathComponent("link").path, withDestinationPath: "top.txt")
        let single = try box.write("one.txt", bytes: 42)

        var last: TransferProgress?
        let r = run([tree, single], progress: { last = $0 })
        #expect(r.outcomes.allSatisfy { $0.status == .done })
        let t = dest.appendingPathComponent("tree")
        #expect(read(t.appendingPathComponent("sub/deep.bin"))?.count == 5000)
        var st = stat()
        #expect(lstat(t.appendingPathComponent("link").path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK)
        #expect(read(dest.appendingPathComponent("one.txt"))?.count == 42)
        #expect(exists(tree) && exists(single))
        #expect(r.batch?.ops.count == 2)
        #expect(store.batches.count == 1)
        #expect(last?.completedItems == 2 && last?.totalItems == 2)
        #expect(last?.completedBytes == last?.totalBytes)
        #expect(listing().allSatisfy { !$0.hasPrefix(".pinax-partial-") })
    }

    @Test func copyWithoutCloneStillWorks() throws {
        let f = try box.write("big.bin", bytes: 3_000_000)
        let plan = TransferPlan.make(sources: [f], destination: dest, kind: .copy)
        let r = TransferRunner(executor: box.executor(journal: store), home: box.home, trasher: trasher, allowClone: false)
            .run(plan: plan, policy: .skip, title: "T")
        #expect(r.outcomes.first?.status == .done)
        #expect(read(dest.appendingPathComponent("big.bin"))?.count == 3_000_000)
    }

    @Test func undoCopyTrashesCreated() throws {
        let f = try box.write("a.txt")
        let r = run([f])
        let created = dest.appendingPathComponent("a.txt")
        #expect(r.batch?.ops == [.copy(source: f, created: created)])
        let out = box.executor(journal: store).undo(batch: r.batch!, trasher: trasher)
        #expect(out.first?.status == .done)
        #expect(!exists(created) && exists(f))
        #expect(trashContents().count == 1)
        // Lần hai: bản chép không còn.
        let out2 = box.executor(journal: store).undo(batch: r.batch!, trasher: trasher)
        #expect(out2.first?.status == .skipped(.missing))
    }

    // MARK: move

    @Test func sameVolumeMove() throws {
        let f = try box.write("m.txt")
        let r = run([f], kind: .move)
        let to = dest.appendingPathComponent("m.txt")
        #expect(r.outcomes.first?.status == .done)
        #expect(exists(to) && !exists(f))
        #expect(r.batch?.ops == [.move(from: f, to: to)])
    }

    @Test func crossVolumeMoveTrashesSourceAndUndoRestores() throws {
        let f = try box.write("x.txt", bytes: 77)
        let r = run([f], kind: .move, sameVolume: false)
        let to = dest.appendingPathComponent("x.txt")
        #expect(r.outcomes.first?.status == .done)
        #expect(exists(to) && !exists(f))
        #expect(trashContents().count == 1)
        guard case let .copy(s, c)? = r.batch?.ops.first, case .trash(let o, _)? = r.batch?.ops.last else {
            Issue.record("ops sai thứ tự: \(String(describing: r.batch?.ops))"); return
        }
        #expect(s == f && c == to && o == f && r.batch?.ops.count == 2)

        box.executor(journal: store).undo(batch: r.batch!, trasher: trasher)
        #expect(exists(f) && !exists(to))
        #expect(read(f)?.count == 77)
    }

    // MARK: xung đột

    @Test func replaceThenUndoRestoresOld() throws {
        let src = try box.write("r.txt", bytes: 10)
        let old = try box.write("r.txt", in: dest, bytes: 99)
        let r = run([src], policy: .replace)
        #expect(r.outcomes.first?.status == .done)
        #expect(read(old)?.count == 10)
        #expect(r.batch?.ops.count == 2)
        box.executor(journal: store).undo(batch: r.batch!, trasher: trasher)
        #expect(read(old)?.count == 99)
        #expect(exists(src))
    }

    @Test func replaceRefusesWhenOldItemContainsSource() throws {
        let outer = dest.appendingPathComponent("foo", isDirectory: true)
        try fm.createDirectory(at: outer, withIntermediateDirectories: true)
        let inner = try box.write("foo", in: outer, bytes: 5)
        let r = run([inner], kind: .move, policy: .replace)
        #expect(r.outcomes.first?.status == .skipped(.intoItself))
        #expect(exists(inner) && r.batch == nil && trashContents().isEmpty)
    }

    @Test func keepBothAndSkip() throws {
        let src = try box.write("k.txt", bytes: 10)
        let old = try box.write("k.txt", in: dest, bytes: 99)
        let r = run([src], policy: .keepBoth)
        #expect(r.outcomes.first?.status == .done)
        #expect(read(old)?.count == 99)
        #expect(read(dest.appendingPathComponent("k 2.txt"))?.count == 10)

        let r2 = run([src], policy: .skip)
        #expect(r2.outcomes.first?.status == .skipped(.destinationExists))
        #expect(r2.batch == nil)
        #expect(!exists(dest.appendingPathComponent("k 3.txt")))
    }

    // MARK: huỷ

    @Test func cancelMidRunKeepsFirstAndSkipsRest() throws {
        let files = try ["1.bin", "2.bin", "3.bin"].map { try box.write($0, bytes: 2000) }
        var cancel = false
        let r = run(files, progress: { if $0.completedItems >= 1 { cancel = true } }, isCancelled: { cancel })
        #expect(r.outcomes.map(\.status) == [.done, .skipped(.cancelled), .skipped(.cancelled)])
        #expect(exists(dest.appendingPathComponent("1.bin")))
        #expect(!exists(dest.appendingPathComponent("2.bin")))
        #expect(r.batch?.ops.count == 1)
        #expect(store.batches.count == 1)
        #expect(listing().allSatisfy { !$0.hasPrefix(".pinax-partial-") })
    }

    @Test func cancelInsideCopyCleansPartial() throws {
        let f = try box.write("big.bin", bytes: 4_000_000)
        let r = TransferRunner(executor: box.executor(journal: store), home: box.home, trasher: trasher, allowClone: false)
            .run(plan: TransferPlan.make(sources: [f], destination: dest, kind: .copy), policy: .skip, title: "T",
                 isCancelled: { true })
        #expect(r.outcomes.first?.status == .skipped(.cancelled))
        #expect(r.batch == nil)
        #expect(listing().isEmpty)
    }

    // MARK: PathGuard + dung lượng

    @Test func pathGuardBlocksProtectedDestinationAndMoveSource() throws {
        let f = try box.write("g.txt")
        let lib = box.root.appendingPathComponent("outside", isDirectory: true) // ngoài home → PathGuard từ chối
        try fm.createDirectory(at: lib, withIntermediateDirectories: true)
        let r = run([f], to: lib)
        #expect(r.outcomes.first?.status == .skipped(.protectedPath))
        #expect(!exists(lib.appendingPathComponent("g.txt")))

        let docs = box.home.appendingPathComponent("Documents", isDirectory: true)
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        let r2 = run([docs], kind: .move)
        #expect(r2.outcomes.first?.status == .skipped(.protectedPath))
        #expect(exists(docs))
        // Copy từ nguồn được bảo vệ thì được.
        let r3 = run([docs], kind: .copy)
        #expect(r3.outcomes.first?.status == .done)
    }

    @Test func insufficientSpaceRejectsWholeRun() throws {
        let a = try box.write("a.bin", bytes: 5000)
        let b = try box.write("b.bin", bytes: 5000)
        let r = run([a, b], kind: .move, sameVolume: false, space: { _ in 100 })
        #expect(r.outcomes.map(\.status) == [.skipped(.insufficientSpace), .skipped(.insufficientSpace)])
        #expect(r.batch == nil)
        #expect(exists(a) && exists(b) && listing().isEmpty)
        // Đủ chỗ thì chạy.
        let ok = run([a], kind: .move, sameVolume: false, space: { _ in 1_000_000 })
        #expect(ok.outcomes.first?.status == .done)
    }

    @Test func partialNameFitsIn255Bytes() {
        let n = TransferRunner.partialName(for: String(repeating: "é", count: 200))
        #expect(n.utf8.count <= 255 && n.hasPrefix(".pinax-partial-"))
    }

    // MARK: journal

    @Test func journalWithoutCopyStillDecodesAndCopyRoundTrips() throws {
        let json = """
        [{"date":"2024-01-01T00:00:00Z","id":"11111111-2222-3333-4444-555555555555","title":"Old","undone":false,
          "ops":[{"trash":{"original":"file:\\/\\/\\/a","trashed":"file:\\/\\/\\/b"}},
                 {"move":{"from":"file:\\/\\/\\/c","to":"file:\\/\\/\\/d"}},
                 {"createDir":{"_0":"file:\\/\\/\\/e"}}]}]
        """
        try fm.createDirectory(at: box.journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: box.journalURL)
        #expect(JournalStore(url: box.journalURL).batches.first?.ops.count == 3)

        let op = JournalOp.copy(source: URL(string: "file:///s")!, created: URL(string: "file:///t")!)
        let data = try JSONEncoder().encode([op])
        let back = try JSONDecoder().decode([JournalOp].self, from: data)
        #expect(back == [op])
    }
}
