import Testing
import Foundation
@testable import PinaxCore

@Suite struct DirectoryListerTests {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    @Test func listsHiddenSymlinkPackageAndFolders() async throws {
        let dir = box.downloads
        try box.write("a.txt", bytes: 10)
        try box.write(".secret", bytes: 1)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Folder"), withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("Thing.app"), withIntermediateDirectories: false)
        try Data().write(to: dir.appendingPathComponent("Thing.app/x"))
        try FileManager.default.createSymbolicLink(at: dir.appendingPathComponent("link"),
                                                   withDestinationURL: dir.appendingPathComponent("a.txt"))

        let visible = try await DirectoryLister.list(dir, showHidden: false)
        #expect(Set(visible.map(\.name)) == ["a.txt", "Folder", "Thing.app", "link"])
        let all = try await DirectoryLister.list(dir, showHidden: true)
        #expect(all.count == 5)

        let by = Dictionary(uniqueKeysWithValues: all.map { ($0.name, $0) })
        #expect(by[".secret"]?.isHidden == true)
        #expect(by["a.txt"]?.size == 10 && by["a.txt"]?.isDirectory == false)
        #expect(by["Folder"]?.isNavigableFolder == true && by["Folder"]?.size == nil)
        #expect(by["Thing.app"]?.isPackage == true && by["Thing.app"]?.isNavigableFolder == false)
        #expect(by["link"]?.isSymlink == true)
        #expect(by["a.txt"]?.modified != nil)
    }

    @Test func derivesKindAndPackageWithoutHeavyKeys() async throws {
        let dir = box.downloads
        let fm = FileManager.default
        try box.write("a.txt", bytes: 3)
        try fm.createDirectory(at: dir.appendingPathComponent("Folder"), withIntermediateDirectories: false)
        try fm.createDirectory(at: dir.appendingPathComponent("X.app/Contents"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(at: dir.appendingPathComponent("lnk"), withDestinationURL: dir.appendingPathComponent("a.txt"))
        try fm.createSymbolicLink(at: dir.appendingPathComponent("lnkdir"), withDestinationURL: dir.appendingPathComponent("Folder"))
        let by = Dictionary(uniqueKeysWithValues: try await DirectoryLister.list(dir, showHidden: false).map { ($0.name, $0) })

        #expect(by["a.txt"]?.contentType?.conforms(to: .plainText) == true)
        #expect(by["a.txt"]?.kindDescription.isEmpty == false)
        #expect(by["Folder"]?.contentType == .folder && by["Folder"]?.isPackage == false)
        #expect(by["Folder"]?.kindDescription.isEmpty == false)
        // Giả .app trong thư mục tạm: nếu macOS nhận là package thì phải là package và không đi vào được.
        let app = try #require(by["X.app"])
        #expect(app.isNavigableFolder == !app.isPackage)
        #expect(!app.kindDescription.isEmpty)
        for n in ["lnk", "lnkdir"] {
            let l = try #require(by[n])
            #expect(l.isSymlink && !l.isPackage && !l.kindDescription.isEmpty)
        }
        #expect(by["a.txt"]?.tagNames.isEmpty == true && by["a.txt"]?.ubiquitousStatus == nil)
        let detailed = by["a.txt"]!.loadingDetails()
        #expect(detailed.url == by["a.txt"]!.url && detailed.tagNames.isEmpty)
    }

    @Test func perf10kFiles() async throws {
        guard ProcessInfo.processInfo.environment["PINAX_PERF"] == "1" else { return }
        for i in 0..<10_000 { FileManager.default.createFile(atPath: box.downloads.appendingPathComponent("f\(i).txt").path, contents: nil) }
        let t0 = DispatchTime.now().uptimeNanoseconds
        let items = try await DirectoryLister.list(box.downloads, showHidden: false)
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000
        print("[PINAX_PERF] list 10k: \(ms) ms")
        #expect(items.count == 10_000)
        #expect(ms < 500)
    }

    @Test func throwsOnMissingDirectoryAndHonoursCancellation() async throws {
        await #expect(throws: (any Error).self) {
            _ = try await DirectoryLister.list(box.root.appendingPathComponent("nope"), showHidden: false)
        }
        for i in 0..<50 { try box.write("f\(i)") }
        let task = Task { () throws -> [FileItem] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await DirectoryLister.list(box.downloads, showHidden: false)
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}

@Suite struct FileSortTests {
    func item(_ name: String, dir: Bool = false, size: Int64? = nil, mod: Double? = nil, kind: String = "") -> FileItem {
        FileItem(url: URL(fileURLWithPath: "/t/\(name)"), name: name, isDirectory: dir, size: size,
                 modified: mod.map { Date(timeIntervalSince1970: $0) }, kindDescription: kind)
    }

    lazy var items = [
        item("file10.txt", size: 5, mod: 300, kind: "Text"),
        item("file2.txt", size: 50, mod: 100, kind: "Text"),
        item("Zeta", dir: true, mod: 200, kind: "Folder"),
        item("alpha", dir: true, mod: 400, kind: "Folder"),
        item("img.png", size: 20, mod: 200, kind: "PNG image"),
    ]

    @Test mutating func nameFoldersFirstNatural() {
        let r = FileSort().sorted(items).map(\.name)
        #expect(r == ["alpha", "Zeta", "file2.txt", "file10.txt", "img.png"])
        let d = FileSort(ascending: false).sorted(items).map(\.name)
        #expect(d == ["Zeta", "alpha", "img.png", "file10.txt", "file2.txt"])
    }

    @Test mutating func nameWithoutFoldersFirst() {
        let r = FileSort(foldersFirst: false).sorted(items).map(\.name)
        #expect(r == ["alpha", "file2.txt", "file10.txt", "img.png", "Zeta"])
    }

    @Test mutating func modifiedSizeKind() {
        #expect(FileSort(key: .modified).sorted(items).map(\.name) == ["Zeta", "alpha", "file2.txt", "img.png", "file10.txt"])
        #expect(FileSort(key: .size, ascending: false).sorted(items).map(\.name) == ["alpha", "Zeta", "file2.txt", "img.png", "file10.txt"])
        // Folder < PNG image < Text; thư mục đứng đầu; hoà thì theo tên.
        #expect(FileSort(key: .kind).sorted(items).map(\.name) == ["alpha", "Zeta", "img.png", "file2.txt", "file10.txt"])
    }
}

/// Gom event từ thread khác.
private final class Events: @unchecked Sendable {
    private let lock = NSLock()
    private var list: [DirectoryWatcher.Event] = []
    func add(_ e: DirectoryWatcher.Event) { lock.withLock { list.append(e) } }
    var all: [DirectoryWatcher.Event] { lock.withLock { list } }
    func wait(for e: DirectoryWatcher.Event, seconds: Double) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if all.contains(e) { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return all.contains(e)
    }
}

@Suite struct DirectoryWatcherTests {
    @Test func reportsChangedWithinOneSecond() async throws {
        let box = try Sandbox()
        let events = Events()
        let w = try #require(DirectoryWatcher(url: box.downloads) { events.add($0) })
        try box.write("new.txt")
        #expect(await events.wait(for: .changed, seconds: 1))
        w.stop()
    }

    @Test func reportsVanishedWhenDirectoryRemoved() async throws {
        let box = try Sandbox()
        let dir = box.home.appendingPathComponent("watched")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false)
        let events = Events()
        let w = try #require(DirectoryWatcher(url: dir) { events.add($0) })
        try FileManager.default.removeItem(at: dir) // thư mục tạm của test
        #expect(await events.wait(for: .vanished, seconds: 1))
        w.stop()
    }

    @Test func stopSilencesFurtherEventsAndMissingDirIsNil() async throws {
        let box = try Sandbox()
        let events = Events()
        let w = try #require(DirectoryWatcher(url: box.downloads) { events.add($0) })
        w.stop()
        try box.write("x.txt")
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(events.all.isEmpty)
        #expect(DirectoryWatcher(url: box.root.appendingPathComponent("nope")) { _ in } == nil)
    }

    @Test func debouncesBurstIntoOneEvent() async throws {
        let box = try Sandbox()
        let events = Events()
        let w = try #require(DirectoryWatcher(url: box.downloads, debounce: 0.2) { events.add($0) })
        for i in 0..<5 { try box.write("b\(i).txt") }
        #expect(await events.wait(for: .changed, seconds: 1))
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(events.all.count == 1)
        w.stop()
    }
}

@Suite struct PathCompletionTests {
    let box: Sandbox
    init() throws {
        box = try Sandbox()
        for d in ["Documents", "Downloads", "dev", ".config", "Desktop"] {
            try FileManager.default.createDirectory(at: box.home.appendingPathComponent(d), withIntermediateDirectories: true)
        }
        try box.write("Dfile.txt", in: box.home)
        try FileManager.default.createSymbolicLink(at: box.home.appendingPathComponent("Dlink"),
                                                   withDestinationURL: box.home.appendingPathComponent("Desktop"))
    }

    @Test func tildePrefixCaseInsensitiveFoldersOnly() {
        let r = PathCompletion.complete("~/d", home: box.home)
        #expect(r == ["~/Desktop/", "~/dev/", "~/Dlink/", "~/Documents/", "~/Downloads/"])
        #expect(PathCompletion.complete("~/do", home: box.home) == ["~/Documents/", "~/Downloads/"])
    }

    @Test func trailingSlashListsChildrenAndHiddenNeedsDot() {
        let r = PathCompletion.complete("~/", home: box.home)
        #expect(!r.contains("~/.config/") && r.contains("~/Documents/") && !r.contains("~/Dfile.txt/"))
        #expect(PathCompletion.complete("~/.c", home: box.home) == ["~/.config/"])
        #expect(PathCompletion.complete("~", home: box.home) == ["~/"])
    }

    @Test func absoluteAndNestedAndInvalid() {
        #expect(PathCompletion.complete(box.home.path + "/Doc", home: box.home) == [box.home.path + "/Documents/"])
        #expect(PathCompletion.complete("~/Nope/x", home: box.home).isEmpty)
        #expect(PathCompletion.complete("relative", home: box.home).isEmpty)
        #expect(PathCompletion.complete("", home: box.home).isEmpty)
    }

    @Test func capsAtFifty() throws {
        let big = box.home.appendingPathComponent("big")
        for i in 0..<80 { try FileManager.default.createDirectory(at: big.appendingPathComponent("d\(i)"), withIntermediateDirectories: true) }
        #expect(PathCompletion.complete("~/big/", home: box.home).count == 50)
    }
}

@Suite struct AppCatalogTests {
    @Test func returnsOnlyResolvableApps() {
        let present: Set<String> = ["com.apple.Terminal", "dev.zed.Zed", "com.microsoft.VSCode"]
        let resolve: (String) -> URL? = { present.contains($0) ? URL(fileURLWithPath: "/Applications/\($0).app") : nil }
        let terms = AppCatalog.installedTerminals(resolve: resolve)
        #expect(terms.map(\.bundleID) == ["com.apple.Terminal"])
        let eds = AppCatalog.installedEditors(resolve: resolve)
        #expect(eds.map(\.bundleID) == ["com.microsoft.VSCode", "dev.zed.Zed"])
        #expect(AppCatalog.installedEditors(resolve: { _ in nil }).isEmpty)
    }

    @Test func catalogContainsPlanIDs() {
        #expect(AppCatalog.terminalBundleIDs.count == 4)
        #expect(AppCatalog.editorBundleIDs.count == 11)
        #expect(AppCatalog.editorBundleIDs.contains("com.todesktop.230313mzl4w4u92"))
    }
}
