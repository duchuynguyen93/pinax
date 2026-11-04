import Testing
import Foundation
@testable import PinaxCore

@Suite struct JournalCompatTests {
    /// journal.json do 0.1.x ghi (đóng băng). Đổi `JournalOp`/`Batch` mà test này đỏ = làm hỏng lịch sử của người dùng.
    static let fixture = """
    [
      {
        "date" : "2023-11-14T22:13:20Z",
        "id" : "11111111-2222-3333-4444-555555555555",
        "ops" : [
          { "trash" : { "original" : "file:\\/\\/\\/Users\\/x\\/Downloads\\/a.dmg", "trashed" : "file:\\/\\/\\/Users\\/x\\/.Trash\\/a.dmg" } },
          { "move" : { "from" : "file:\\/\\/\\/Users\\/x\\/Downloads\\/b.pdf", "to" : "file:\\/\\/\\/Users\\/x\\/Downloads\\/Documents\\/b.pdf" } },
          { "createDir" : { "_0" : "file:\\/\\/\\/Users\\/x\\/Downloads\\/Documents" } }
        ],
        "title" : "Tidy Downloads",
        "undone" : false
      },
      {
        "date" : "2023-11-15T08:00:00Z",
        "id" : "66666666-7777-8888-9999-000000000000",
        "ops" : [],
        "title" : "Old",
        "undone" : true
      }
    ]
    """

    @Test func decodesZeroPointOneJournal() throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.journalURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.fixture.utf8).write(to: box.journalURL)
        let store = JournalStore(url: box.journalURL)
        #expect(store.batches.count == 2)
        let first = store.batches[0]
        #expect(first.title == "Tidy Downloads")
        #expect(first.undone == false)
        #expect(first.ops == [
            .trash(original: URL(string: "file:///Users/x/Downloads/a.dmg")!, trashed: URL(string: "file:///Users/x/.Trash/a.dmg")!),
            .move(from: URL(string: "file:///Users/x/Downloads/b.pdf")!, to: URL(string: "file:///Users/x/Downloads/Documents/b.pdf")!),
            .createDir(URL(string: "file:///Users/x/Downloads/Documents")!),
        ])
        #expect(store.batches[1].undone)
        // Không bị coi là file hỏng.
        #expect(!FileManager.default.fileExists(atPath: box.journalURL.deletingLastPathComponent().appendingPathComponent("journal.corrupt.json").path))
    }
}
