import AppKit
import PinaxCore

/// PINAX_QA_SCRIPT=<cut|rename|tag|expand> (QA, dùng cùng PINAX_OPEN, chỉ cửa sổ đầu): chạy một kịch bản gọi ĐÚNG các hàm
/// model mà menu / phím tắt gọi (không bơm phím), log ra stderr với tiền tố `[Pinax QA] `. Xong thì để app chạy tiếp.
/// Hoàn tác chỉ nhắm đúng batch do kịch bản tạo (nhận diện bằng id mới + op khớp); không chắc thì FAIL và không hoàn tác gì.
@MainActor
enum QAScript {
    private static var consumed = false

    /// Tên kịch bản nếu env đặt (không đánh dấu đã dùng).
    static var name: String? {
        ProcessInfo.processInfo.environment["PINAX_QA_SCRIPT"].flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `expand`: PreviewPane tự mở rộng thư mục con đầu tiên.
    static var expandsPreview: Bool { name == "expand" }

    private struct Failure: Error { let reason: String }

    static func log(_ s: String) {
        FileHandle.standardError.write(Data("[Pinax QA] \(s)\n".utf8))
    }

    static func run(window: WindowModel, env: AppEnvironment) async {
        guard !consumed, let name else { return }
        consumed = true
        let m = window.primary
        for _ in 0..<100 where m.isLoading { try? await Task.sleep(for: .milliseconds(50)) }
        try? await Task.sleep(for: .seconds(1))
        log("script=\(name) folder=\(m.folder.path)")
        do {
            switch name {
            case "cut": try await cut(m, env)
            case "rename": try await rename(m, env)
            case "tag": try await tag(m)
            case "expand": try await expand(m)
            default: throw Failure(reason: "unknown script \(name)")
            }
            log("DONE")
        } catch let f as Failure {
            log("FAIL \(f.reason)")
        } catch {
            log("FAIL \(error)")
        }
    }

    // MARK: Kịch bản

    private static func cut(_ m: BrowserModel, _ env: AppEnvironment) async throws {
        let dir = m.folder
        let a = dir.appendingPathComponent("a.txt"), b = dir.appendingPathComponent("b.txt")
        let dest = dir.appendingPathComponent("dest", isDirectory: true)
        let fm = FileManager.default
        for u in [a, b, dest] where !fm.fileExists(atPath: u.path) { throw Failure(reason: "missing \(u.lastPathComponent)") }
        // Trùng tên ở đích sẽ bật hộp thoại hỏi → không chạy.
        for n in ["a.txt", "b.txt"] where fm.fileExists(atPath: dest.appendingPathComponent(n).path) {
            throw Failure(reason: "dest/\(n) already exists")
        }

        m.selection = [a.path, b.path]
        m.cutSelectionToPasteboard()
        log("cut: isActive=\(ClipboardCut.isActive) a=\(ClipboardCut.isCut(a.path)) b=\(ClipboardCut.isCut(b.path)) "
            + "alpha(a)=\(ClipboardCut.alpha(a.path))")
        try? await Task.sleep(for: .seconds(3))

        m.navigate(to: dest)
        try await waitFolder(m, dest)
        let before = Set(env.history.batches.map(\.id))
        m.pasteFromPasteboard(move: false)
        let batch = try await waitNewBatch(env, before: before, timeout: 15)
        log("paste: batch title=\"\(batch.title)\" ops=\(batch.ops.count) transferActive=\(env.transfers.isActive)")
        log("after paste: dest/a.txt=\(exists(dest, "a.txt")) dest/b.txt=\(exists(dest, "b.txt")) "
            + "orig a.txt=\(exists(dir, "a.txt")) orig b.txt=\(exists(dir, "b.txt")) cutActive=\(ClipboardCut.isActive)")

        try verify(batch, expecting: [(a, dest.appendingPathComponent("a.txt")), (b, dest.appendingPathComponent("b.txt"))])
        try await undo(batch, env)
        log("after undo: orig a.txt=\(exists(dir, "a.txt")) orig b.txt=\(exists(dir, "b.txt")) "
            + "dest/a.txt=\(exists(dest, "a.txt")) dest/b.txt=\(exists(dest, "b.txt"))")
        log("toast: \(env.toast.current?.message ?? "nil")")
    }

    private static func rename(_ m: BrowserModel, _ env: AppEnvironment) async throws {
        let dir = m.folder
        let urls = (1...3).map { dir.appendingPathComponent("IMG_\($0).jpg") }
        for u in urls where !FileManager.default.fileExists(atPath: u.path) { throw Failure(reason: "missing \(u.lastPathComponent)") }

        m.selection = Set(urls.map(\.path))
        // Thứ tự như sheet: theo thứ tự đang hiển thị.
        let ordered = m.selectedItems.map(\.url)
        let entries = BatchRename.plan(ordered, rule: .replace(find: "IMG_", with: "Photo ", caseSensitive: false, includeExtension: false))
        log("plan: " + entries.map { "\($0.source.lastPathComponent)->\($0.newName)\($0.issue == nil ? "" : "(issue)")" }.joined(separator: ", "))
        guard entries.count == 3, entries.allSatisfy({ $0.issue == nil }) else { throw Failure(reason: "plan has issues") }

        let before = Set(env.history.batches.map(\.id))
        m.applyBatchRename(entries: entries)
        let batch = try await waitNewBatch(env, before: before, timeout: 10)
        try? await Task.sleep(for: .milliseconds(500))
        log("after rename: listing=\(listing(dir))")
        log("toast: \(env.toast.current?.message ?? "nil")")

        try verify(batch, expecting: entries.map { ($0.source, $0.target) })
        try await undo(batch, env)
        log("after undo: listing=\(listing(dir))")
        log("toast: \(env.toast.current?.message ?? "nil")")
    }

    private static func tag(_ m: BrowserModel) async throws {
        let t = m.folder.appendingPathComponent("t.txt")
        guard FileManager.default.fileExists(atPath: t.path) else { throw Failure(reason: "missing t.txt") }
        guard let red = TagSupport.standard.first?.name else { throw Failure(reason: "no standard tags") }
        m.selection = [t.path]
        log("tag name=\(red) initial=\(TagSupport.tags(of: t))")
        for step in 1...3 {
            let prev = TagSupport.tags(of: t)
            m.toggleTag(red)
            // toggleTag ghi ở nền → chờ tới khi tag đổi.
            var changed = false
            for _ in 0..<60 {
                try? await Task.sleep(for: .milliseconds(100))
                if TagSupport.tags(of: t) != prev { changed = true; break }
            }
            try? await Task.sleep(for: .milliseconds(300))
            log("toggle \(step): changed=\(changed) tagNames=\(TagSupport.tags(of: t))")
            if !changed { throw Failure(reason: "tag did not change at step \(step)") }
        }
        log("final tagNames=\(TagSupport.tags(of: t))")
    }

    private static func expand(_ m: BrowserModel) async throws {
        let dest = m.folder.appendingPathComponent("dest", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dest.path) else { throw Failure(reason: "missing dest") }
        // Xem trước bật bằng BrowserPrefs.init (không ghi UserDefaults); chỉ kiểm tra.
        log("showPreview=\(m.prefs.showPreview)")
        guard m.prefs.showPreview else { throw Failure(reason: "preview pane is off") }
        let kids = (try? FileManager.default.contentsOfDirectory(atPath: dest.path)) ?? []
        log("dest children=\(kids.sorted())")
        m.selection = [dest.path]
        // PreviewPane nạp sau 120 ms rồi tự mở thư mục con đầu tiên (QAScript.expandsPreview).
        try? await Task.sleep(for: .seconds(2))
        log("selected=\(m.selection.sorted())")
    }

    // MARK: Hỗ trợ

    private static func exists(_ dir: URL, _ n: String) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent(n).path)
    }

    private static func listing(_ dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }

    private static func key(_ u: URL) -> String { u.resolvingSymlinksInPath().standardizedFileURL.path }

    private static func waitFolder(_ m: BrowserModel, _ url: URL) async throws {
        for _ in 0..<100 {
            if key(m.folder) == key(url), !m.isLoading { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
        throw Failure(reason: "folder did not load: \(url.path)")
    }

    /// Chờ tới khi có đúng một batch mới (id chưa có trong `before`) và hàng đợi chép / chuyển rảnh.
    private static func waitNewBatch(_ env: AppEnvironment, before: Set<UUID>, timeout: Double) async throws -> Batch {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let fresh = env.history.batches.filter { !before.contains($0.id) }
            if !fresh.isEmpty, !env.transfers.isActive {
                guard fresh.count == 1 else { throw Failure(reason: "\(fresh.count) new batches, cannot identify") }
                return fresh[0]
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        throw Failure(reason: "no new batch within \(Int(timeout))s")
    }

    /// Batch phải gồm đúng các op `.move(from,to)` mong đợi, chưa hoàn tác; không thì FAIL (không hoàn tác gì).
    private static func verify(_ batch: Batch, expecting: [(URL, URL)]) throws {
        var got: [String] = []
        for op in batch.ops {
            guard case .move(let from, let to) = op else { throw Failure(reason: "batch has non-move op, not undoing") }
            got.append("\(key(from)) -> \(key(to))")
        }
        let want = expecting.map { "\(key($0.0)) -> \(key($0.1))" }
        guard !batch.undone, Set(got) == Set(want), got.count == want.count else {
            throw Failure(reason: "batch ops do not match expected, not undoing. got=\(got.sorted()) want=\(want.sorted())")
        }
        log("batch verified: id=\(batch.id) title=\"\(batch.title)\"")
    }

    /// Hoàn tác bằng đường của nút Undo trên toast (`AppEnvironment.undo`), chờ tới khi batch đó `undone`.
    private static func undo(_ batch: Batch, _ env: AppEnvironment) async throws {
        env.undo(batch)
        for _ in 0..<100 {
            try? await Task.sleep(for: .milliseconds(100))
            if env.history.batches.first(where: { $0.id == batch.id })?.undone == true {
                try? await Task.sleep(for: .milliseconds(500))
                log("undo done for batch \(batch.id)")
                return
            }
        }
        throw Failure(reason: "undo did not complete")
    }
}
