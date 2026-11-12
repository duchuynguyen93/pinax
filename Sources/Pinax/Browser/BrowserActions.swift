import AppKit
import PinaxCore

/// Thao tác file của trình duyệt: mọi thứ đi qua `FileOps` → `Executor` (PathGuard, journal, hoàn tác bằng ⌘Z).
extension BrowserModel {
    var fileOps: FileOps { FileOps(executor: Executor(store: history.store), home: home) }

    // MARK: Điều kiện bật / tắt (chỉ để bật tắt menu; Executor vẫn kiểm lại)

    /// Đang xem kết quả tìm đệ quy thì không có thư mục đích (tắt New Folder, Paste, Duplicate).
    var canCreateFolderHere: Bool { pinax == nil && error == nil && !inSubfolderSearch && fileOps.canCreateFolder(in: folder) }

    var canRenameSelection: Bool {
        guard pinax == nil, selection.count == 1, let item = selectedItems.first else { return false }
        return fileOps.canModify(item.url)
    }

    var canBatchRename: Bool {
        guard pinax == nil, selection.count >= 2 else { return false }
        let ops = fileOps
        let sel = selectedItems
        return sel.count >= 2 && sel.allSatisfy { ops.canModify($0.url) }
    }

    var canTrashSelection: Bool {
        guard pinax == nil, !selection.isEmpty else { return false }
        let ops = fileOps
        return selectedItems.contains { ops.canModify($0.url) }
    }

    // MARK: Tag màu

    /// Mục menu Tags bật nếu có ít nhất một mục sửa được.
    var canTagSelection: Bool { canTrashSelection }

    /// Bật / tắt tag `name` trên mọi mục chọn sửa được: mọi mục đã có → bỏ, ngược lại → thêm. Ghi ngoài main.
    func toggleTag(_ name: String) {
        guard canTagSelection else { return }
        let ops = fileOps
        let urls = selectedItems.map(\.url).filter { ops.canModify($0) }
        let add = !urls.allSatisfy { TagSupport.tags(of: $0).contains(name) }
        Task {
            let failed = await Task.detached(priority: .userInitiated) { TagSupport.apply(name, add: add, to: urls) }.value
            if failed > 0 {
                toast.show(L("Couldn't change the tag on \(failed) items", "Không đổi được tag của \(failed) mục"))
            }
            tags.forget(urls.map(\.path))
            reload()
        }
    }

    /// Tag nào mọi mục chọn đều có (để đánh dấu trong menu). Chọn quá nhiều thì bỏ qua cho khỏi đọc đĩa trên main.
    func tagsOnAllSelected() -> Set<String> {
        let sel = selectedItems
        guard !sel.isEmpty, sel.count <= 200 else { return [] }
        var common = Set(TagSupport.tags(of: sel[0].url))
        for item in sel.dropFirst() where !common.isEmpty { common.formIntersection(TagSupport.tags(of: item.url)) }
        return common
    }

    // MARK: New Folder

    func newFolder() {
        guard pinax == nil else { return }
        let r = fileOps.newFolder(in: folder, title: L("New folder", "Thư mục mới"))
        guard let outcome = r.outcomes.first, outcome.status == .done else {
            let status = r.outcomes.first?.status ?? .skipped(.protectedPath)
            alert(L("Couldn't create the folder", "Không tạo được thư mục"),
                  operationFailureText(status, name: FileOps.availableFolderName(in: folder)))
            return
        }
        history.reload()
        reloadAfterOperation(select: [outcome.url.path], rename: outcome.url.path)
        noteJournalError(r)
    }

    // MARK: Rename

    /// Return: đổi tên tại chỗ mục đang chọn (đúng một mục).
    func beginRenameSelection() {
        guard canRenameSelection, let item = selectedItems.first else { return }
        requestRename(item.url.path)
    }

    /// Return / menu khi chọn ≥ 2 mục: mở sheet đổi tên hàng loạt (thứ tự = thứ tự đang hiển thị).
    func beginBatchRename() {
        guard canBatchRename else { return }
        batchRenameItems = selectedItems.map(\.url)
    }

    /// Sheet bấm Rename: chạy ngoài main, xong báo toast có Undo và chọn các tên mới.
    func applyBatchRename(entries: [RenameEntry]) {
        batchRenameItems = nil
        let store = history.store, home = home
        let n = entries.filter { $0.issue == nil }.count
        let title = L("Rename \(n) items", "Đổi tên \(n) mục")
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileOps(executor: Executor(store: store), home: home).batchRename(entries, title: title)
            }.value
            finishBatchRename(result, entries: entries)
        }
    }

    private func finishBatchRename(_ result: PerformResult, entries: [RenameEntry]) {
        history.reload()
        // Đổi chéo đi hai bước qua tên tạm: chỉ đếm bước cuối (nguồn là tên tạm), không đếm gấp đôi.
        let finished = result.outcomes.filter { $0.status == .done }
        let viaTemp = finished.filter { $0.url.lastPathComponent.hasPrefix(".pinax-rename-") }
        let twoStep = result.outcomes.contains { $0.url.lastPathComponent.hasPrefix(".pinax-rename-") }
        let done = twoStep ? viaTemp.count : finished.count
        let problems = result.outcomes.compactMap(Problem.from)
        var message = done > 0 ? L("Renamed \(done) items", "Đã đổi tên \(done) mục") : L("Nothing was renamed", "Chưa đổi được tên mục nào")
        if !problems.isEmpty && done > 0 {
            message += L(" · \(problems.count) skipped or failed", " · \(problems.count) mục bị bỏ qua hoặc lỗi")
        }
        toast.show(message, undoBatch: result.batch, problems: problems)
        reloadAfterOperation(select: Set(entries.filter { $0.issue == nil }.map(\.target.path)))
        noteJournalError(result)
    }

    /// View gọi khi người dùng chốt tên mới. true = đã đổi (hoặc không đổi gì); false = lỗi, view phải trả tên cũ.
    @discardableResult
    func commitRename(path: String, to raw: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let old = url.lastPathComponent
        do {
            let newName = try FileOps.validatedName(raw)
            let r = try fileOps.rename(url, to: newName, title: L("Rename “\(old)” to “\(newName)”", "Đổi tên “\(old)” thành “\(newName)”"))
            guard let outcome = r.outcomes.first, outcome.status == .done else {
                alert(L("Couldn't rename “\(old)”", "Không đổi được tên “\(old)”"),
                      operationFailureText(r.outcomes.first?.status ?? .skipped(.protectedPath), name: newName))
                return false
            }
            history.reload()
            let newPath = url.deletingLastPathComponent().appendingPathComponent(newName).path
            reloadAfterOperation(select: [newPath])
            noteJournalError(r)
            return true
        } catch let e as FileNameError {
            if e == .unchanged { return true }
            alert(L("Couldn't rename “\(old)”", "Không đổi được tên “\(old)”"), fileNameErrorText(e))
            return false
        } catch {
            alert(L("Couldn't rename “\(old)”", "Không đổi được tên “\(old)”"), error.localizedDescription)
            return false
        }
    }

    // MARK: Move to Trash

    func trashSelection() {
        // Phím ⌘⌫ trong ô chữ = xoá về đầu dòng (menu nuốt phím này trước khi tới ô chữ). Bấm chuột vào menu vẫn là xoá file.
        if NSApp.currentEvent?.type == .keyDown, TextEditing.forward(#selector(NSTextView.deleteToBeginningOfLine(_:))) { return }
        guard canTrashSelection else { return }
        let urls = selectedItems.map(\.url)
        let store = history.store, home = home
        let title = L("Move to Trash: \(itemsText(urls.count))", "Chuyển vào Thùng rác: \(itemsText(urls.count))")
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                FileOps(executor: Executor(store: store), home: home).trash(items: urls, title: title)
            }.value
            finishTrash(result)
        }
    }

    private func finishTrash(_ result: PerformResult) {
        history.reload()
        // Đổi chéo đi hai bước qua tên tạm: chỉ đếm bước cuối (nguồn là tên tạm), không đếm gấp đôi.
        let finished = result.outcomes.filter { $0.status == .done }
        let viaTemp = finished.filter { $0.url.lastPathComponent.hasPrefix(".pinax-rename-") }
        let twoStep = result.outcomes.contains { $0.url.lastPathComponent.hasPrefix(".pinax-rename-") }
        let done = twoStep ? viaTemp.count : finished.count
        let problems = result.outcomes.compactMap(Problem.from)
        var message: String
        if done > 0 {
            message = movedToTrashText(done)
        } else if result.outcomes.allSatisfy({ $0.status == .skipped(.protectedPath) }) {
            message = protectedLocationText()
        } else {
            message = L("Nothing was moved", "Chưa chuyển được mục nào")
        }
        if !problems.isEmpty && done > 0 {
            message += L(" · \(problems.count) skipped or failed", " · \(problems.count) mục bị bỏ qua hoặc lỗi")
        }
        if let e = result.journalError {
            message += L(" · history could not be saved: \(e)", " · không ghi được lịch sử: \(e)")
        }
        toast.show(message, undoBatch: result.batch, problems: problems)
        reload()
    }

    // MARK: Copy Path, Show in Finder

    /// Đường dẫn POSIX thuần, mỗi dòng một đường dẫn; không chọn gì thì chép đường dẫn thư mục hiện tại.
    func copyPath() {
        guard pinax == nil else { return }
        let paths = selection.isEmpty ? [folder.path] : selectedItems.map(\.url.path)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(paths.joined(separator: "\n"), forType: .string)
    }

    func showInFinder() {
        guard pinax == nil else { return }
        if selection.isEmpty {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(selectedItems.map(\.url))
        }
    }

    // MARK: Hộp thoại

    private func noteJournalError(_ r: PerformResult) {
        if let e = r.journalError {
            toast.show(L("History could not be saved: \(e)", "Không ghi được lịch sử: \(e)"))
        }
    }

    func alert(_ message: String, _ detail: String) {
        let a = NSAlert()
        a.alertStyle = .warning
        a.messageText = message
        a.informativeText = detail
        a.addButton(withTitle: L("OK", "OK"))
        if let w = window ?? NSApp.keyWindow {
            a.beginSheetModal(for: w)
        } else {
            a.runModal()
        }
    }
}
