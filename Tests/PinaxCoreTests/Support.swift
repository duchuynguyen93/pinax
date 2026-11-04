import Foundation
@testable import PinaxCore

/// Thư mục tạm giả làm home; trash giả nằm ngoài home.
final class Sandbox {
    let root: URL
    let home: URL
    let trash: URL
    let apps: URL
    let journalURL: URL

    init() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("pinax-test-\(UUID().uuidString)", isDirectory: true)
        root = base.resolvingSymlinksInPath()
        home = root.appendingPathComponent("home", isDirectory: true)
        trash = root.appendingPathComponent("faketrash", isDirectory: true)
        apps = root.appendingPathComponent("Applications", isDirectory: true)
        journalURL = root.appendingPathComponent("support/journal.json")
        for d in [home, trash, apps, home.appendingPathComponent("Downloads")] {
            try fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    deinit { try? FileManager.default.removeItem(at: root) } // chỉ dọn thư mục tạm của chính test

    var downloads: URL { home.appendingPathComponent("Downloads") }

    @discardableResult
    func write(_ name: String, in dir: URL? = nil, bytes: Int = 100) throws -> URL {
        let url = (dir ?? downloads).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 7, count: bytes).write(to: url)
        return url
    }

    func candidate(_ url: URL) -> Candidate {
        Candidate(url: url, size: 100, fingerprint: FileFingerprint.read(from: url)!,
                  reason: "test", lastUsed: nil, preselected: true)
    }

    func executor(journal: JournalStore? = nil) -> Executor {
        Executor(store: journal ?? JournalStore(url: journalURL), applicationsRoot: apps)
    }
}

/// Di chuyển vào thư mục trash giả thay vì Thùng rác thật.
struct TempTrasher: Trasher {
    let dir: URL
    func trash(_ url: URL) throws -> URL {
        let dest = dir.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: dest)
        return dest
    }
}
