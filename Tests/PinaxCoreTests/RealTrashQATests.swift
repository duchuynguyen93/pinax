import Foundation
import Testing
@testable import PinaxCore

/// QA thủ công với Thùng rác THẬT: chỉ đụng file `pinax-qa-*` do chính test tạo trong ~/Downloads.
/// Bật bằng PINAX_REAL_TRASH_QA=1. Không chạy trong `swift test` thường.
@Suite struct RealTrashQATests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["PINAX_REAL_TRASH_QA"] == "1"))
    func duplicatesTrashAndUndoWithRealTrash() async throws {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let downloads = home.appendingPathComponent("Downloads")
        let tag = UUID().uuidString.prefix(8)
        let a = downloads.appendingPathComponent("pinax-qa-\(tag)-a.bin")
        let b = downloads.appendingPathComponent("pinax-qa-\(tag)-b.bin")
        let payload = Data((0..<(2 * 1_048_576)).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        try payload.write(to: a)
        try payload.write(to: b)
        defer { // dọn file QA (chỉ file của test) dù pass hay fail
            for u in [a, b] where fm.fileExists(atPath: u.path) { try? fm.trashItem(at: u, resultingItemURL: nil) }
        }

        let roots = [URL(fileURLWithPath: "/Applications")]
        let ctx = ScanContext(home: home, applicationRoots: roots, now: Date(),
                              lastUsed: SpotlightLastUsedProvider(),
                              installedApps: FileSystemInstalledApps(roots: roots),
                              settings: .defaults(home: home))
        let result = await DuplicatesRule().scan(ctx)
        let qa = result.candidates.filter { $0.url.lastPathComponent.hasPrefix("pinax-qa-\(tag)") }
        #expect(qa.count == 1, "one of the two QA copies is a candidate, the other is the keeper")
        guard let victim = qa.first else { return }
        #expect(victim.preselected, "both copies in Downloads → preselected")

        let journalURL = fm.temporaryDirectory.appendingPathComponent("pinax-qa-journal-\(tag).json")
        defer { try? fm.removeItem(at: journalURL) } // file tạm của test
        let executor = Executor(store: JournalStore(url: journalURL))
        let res = executor.perform(candidates: [victim], title: "QA", trasher: FileManagerTrasher(), home: home)
        #expect(res.outcomes.first?.status == .done)
        let batch = try #require(res.batch)
        guard case let .trash(original, trashed) = batch.ops[0] else { Issue.record("expected trash op"); return }
        print("QA trashed → \(trashed.path)")
        #expect(!fm.fileExists(atPath: original.path))
        #expect(fm.fileExists(atPath: trashed.path), "file really is in the Trash")
        let keeper = victim.url == a ? b : a
        #expect(fm.fileExists(atPath: keeper.path), "keeper untouched")

        let undo = executor.undo(batch: batch)
        #expect(undo.first?.status == .done)
        #expect(fm.fileExists(atPath: original.path), "restored to original path")
        #expect(!fm.fileExists(atPath: trashed.path))
        #expect(try Data(contentsOf: original) == payload, "content intact")
    }
}
