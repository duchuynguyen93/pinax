import SwiftUI
import AppKit
import PinaxCore

/// Phím tắt dùng chung cho list và icon view: Space = Quick Look, ⌘↓ = mở, Return = đổi tên.
@MainActor
enum BrowserKeys {
    static func handle(_ event: NSEvent, model: BrowserModel) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if flags.isEmpty, event.charactersIgnoringModifiers == " " {
            model.toggleQuickLook()
            return true
        }
        // Tab / ⇧Tab: đang dual thì chuyển pane; đơn thì giữ hành vi mặc định.
        if event.keyCode == 48, flags.subtracting(.shift).isEmpty, model.windowModel?.isDual == true {
            model.onSwitchPane?()
            return true
        }
        if flags == .command, event.keyCode == 125 {
            model.openSelection()
            return true
        }
        if flags.isEmpty, event.keyCode == 36 || event.keyCode == 76, model.canRenameSelection {
            model.beginRenameSelection()
            return true
        }
        return false
    }
}

/// NSTableView có context menu.
final class BrowserTableView: NSTableView, NSMenuItemValidation {
    var menuProvider: ((NSEvent) -> NSMenu?)?
    weak var model: BrowserModel?
    /// Phím riêng của trình duyệt (Space, ⌘↓); trả true nếu đã xử lý.
    var keyHandler: ((NSEvent) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        super.keyDown(with: event)
    }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok { model?.onActivate?() }
        return ok
    }

    // ⌘C / ⌘V của menu Edit đi qua responder chain tới đây; ô chữ đang gõ giữ ⌘C / ⌘V của nó.
    @objc func copy(_ sender: Any?) { model?.copySelectionToPasteboard() }
    @objc func paste(_ sender: Any?) { model?.pasteFromPasteboard(move: false) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(copy(_:)): model?.canCopySelection ?? false
        case #selector(paste(_:)): model?.canPaste ?? false
        default: true
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        model?.onActivate?()
        // Như Finder: chuột phải vào mục chưa chọn → chọn riêng mục đó; vào chỗ trống → bỏ chọn.
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 {
            if !isRowSelected(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        } else {
            deselectAll(nil)
        }
        return menuProvider?(event) ?? super.menu(for: event)
    }
}

/// Ô của bảng; khi tái dùng thì huỷ request thumbnail đang chạy của nó.
final class ListCell: NSTableCellView {
    weak var requester: ThumbnailRequester?
    var representedPath: String?

    override func prepareForReuse() {
        super.prepareForReuse()
        MainActor.assumeIsolated { requester?.cancel(self) }
        representedPath = nil
    }
}

/// Danh sách file bằng NSTableView (không dùng SwiftUI List).
struct FileListView: NSViewRepresentable {
    let model: BrowserModel
    // Truyền vào dạng giá trị để SwiftUI biết khi nào gọi updateNSView.
    let generation: Int
    let resetToken: Int
    let revealToken: Int
    let sort: FileSort
    let pathEditing: Bool
    let renameToken: Int
    /// Tìm Subfolders → hiện cột Where.
    let showWhere: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let table = BrowserTableView()
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        // Hai khung: mỗi khung hẹp → co đều mọi cột và lưu độ rộng riêng, không thì cột Name đẩy các cột khác ra ngoài.
        let dual = model.windowModel?.isDual == true
        table.columnAutoresizingStyle = dual ? .uniformColumnAutoresizingStyle : .firstColumnOnlyAutoresizingStyle
        table.rowSizeStyle = .default
        table.dataSource = c
        table.delegate = c
        table.target = c
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        // Kéo thả: nguồn kéo cho phép chép / chuyển; thả vào hàng thư mục hoặc cả bảng.
        table.registerForDraggedTypes([.fileURL])
        table.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: true)
        table.setDraggingSourceOperationMask([.copy, .move, .generic], forLocal: false)

        func column(_ id: String, _ title: String, width: CGFloat, min: CGFloat, key: FileSort.Key) -> NSTableColumn {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = min
            col.sortDescriptorPrototype = NSSortDescriptor(key: key.rawValue, ascending: true)
            return col
        }
        table.addTableColumn(column("name", L("Name", "Tên"), width: 340, min: 160, key: .name))
        table.addTableColumn(column("modified", L("Date Modified", "Ngày sửa"), width: 200, min: 100, key: .modified))
        let sizeCol = column("size", L("Size", "Dung lượng"), width: 90, min: 60, key: .size)
        sizeCol.headerCell.alignment = .right
        table.addTableColumn(sizeCol)
        table.addTableColumn(column("kind", L("Kind", "Loại"), width: 150, min: 60, key: .kind))
        // Cột Where thêm sau: layout đã lưu của bản cũ không có nó nên nó nằm cuối; ẩn / hiện đặt lại ở mỗi lần `sync`.
        let whereCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("where"))
        whereCol.title = L("Where", "Vị trí")
        whereCol.width = 200
        whereCol.minWidth = 80
        whereCol.isHidden = true
        table.addTableColumn(whereCol)
        table.autosaveName = dual ? "pinax.browser.list.dual.v1" : "pinax.browser.list.v2"
        table.autosaveTableColumns = true

        let scroll = NSScrollView()
        scroll.documentView = table
        // Bảng mới tạo rộng bằng tổng các cột; co về đúng bề rộng khung sau lần dàn trang đầu.
        if dual { DispatchQueue.main.async { table.sizeToFit() } }
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        c.table = table
        table.model = model
        model.contentView = table
        table.menuProvider = { [weak c] _ in c.map { BrowserMenu.make(model: $0.model) } }
        table.keyHandler = { [weak c] event in
            guard let c else { return false }
            return BrowserKeys.handle(event, model: c.model)
        }
        c.model.folderSizes.observe(c) { [weak c] path in c?.sizeResolved(path) }
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.model.folderSizes.stopObserving(coordinator)
        coordinator.thumbs.cancelAll()
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.model = model
        c.table?.model = model
        model.contentView = c.table
        c.sync(generation: generation, resetToken: resetToken, revealToken: revealToken,
               sort: sort, pathEditing: pathEditing, renameToken: renameToken, showWhere: showWhere)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate {
        var model: BrowserModel
        weak var table: BrowserTableView?
        private var items: [FileItem] = []
        private var rowByPath: [String: Int] = [:]
        private var lastGeneration = -1, lastReset = -1, lastReveal = -1
        private var wasEditingPath = false
        private var didInitialFocus = false
        private var isUpdating = false
        /// Mục đang đổi tên tại chỗ.
        private var editing: (path: String, original: String)?
        private var cancelled = false
        let thumbs = ThumbnailRequester()
        private static let iconPoints: CGFloat = 18

        init(model: BrowserModel) { self.model = model }

        /// Một thư mục vừa tính xong → vẽ lại ô Size của đúng dòng đó.
        func sizeResolved(_ path: String) {
            guard let table, let row = rowByPath[path] else { return }
            let col = table.column(withIdentifier: NSUserInterfaceItemIdentifier("size"))
            guard col >= 0 else { return }
            table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: col))
        }

        func sync(generation: Int, resetToken: Int, revealToken: Int, sort: FileSort, pathEditing: Bool, renameToken: Int = 0,
                  showWhere: Bool) {
            guard let table else { return }
            isUpdating = true
            defer { isUpdating = false }

            // Đặt tường minh mỗi lần: autosave của bảng có thể đã khôi phục trạng thái ẩn / hiện cũ của cột.
            if let col = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("where")), col.isHidden == showWhere {
                // Lấy / trả chỗ từ cột Tên, không co các cột Ngày / Cỡ / Loại (sizeToFit bóp đều mọi cột).
                let name = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("name"))
                if showWhere { col.width = max(col.width, 220) }
                if let name, table.columnAutoresizingStyle == .firstColumnOnlyAutoresizingStyle {
                    name.width = showWhere ? max(name.minWidth, name.width - col.width) : name.width + col.width
                }
                col.isHidden = !showWhere
                if table.columnAutoresizingStyle != .firstColumnOnlyAutoresizingStyle { table.sizeToFit() }
            }

            let desc = NSSortDescriptor(key: sort.key.rawValue, ascending: sort.ascending)
            if table.sortDescriptors.first.map({ $0.key != desc.key || $0.ascending != desc.ascending }) ?? true {
                table.sortDescriptors = [desc]
            }

            // Đang gõ tên mới thì chưa nạp lại bảng (watcher báo ngay sau New Folder); nạp khi gõ xong.
            if generation != lastGeneration, editing == nil {
                lastGeneration = generation
                if resetToken != lastReset { thumbs.cancelAll() }
                items = model.items
                rowByPath = Dictionary(items.enumerated().map { ($1.url.path, $0) }, uniquingKeysWith: { a, _ in a })
                table.reloadData()
                let rows = IndexSet(model.selection.compactMap { rowByPath[$0] })
                table.selectRowIndexes(rows, byExtendingSelection: false)
                if resetToken != lastReset {
                    lastReset = resetToken
                    if !items.isEmpty { table.scrollRowToVisible(0) }
                }
                if revealToken != lastReveal {
                    lastReveal = revealToken
                    if let first = rows.first { table.scrollRowToVisible(first) }
                }
                if let start = model.navStart {
                    model.navStart = nil
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    FileHandle.standardError.write(Data(String(
                        format: "[Pinax perf] %d items: navigation start -> table reload %.1f ms\n", items.count, ms).utf8))
                }
                if !didInitialFocus, !items.isEmpty, !pathEditing, model.isActivePane {
                    didInitialFocus = true
                    table.window?.makeFirstResponder(table)
                }
            }

            // Thoát ⌘L → trả focus cho bảng để type-to-select / phím mũi tên chạy tiếp.
            if wasEditingPath, !pathEditing { table.window?.makeFirstResponder(table) }
            wasEditingPath = pathEditing

            if let path = model.pendingRename, editing == nil, rowByPath[path] != nil {
                model.pendingRename = nil
                DispatchQueue.main.async { [weak self] in self?.beginRename(path: path) }
            }
        }

        // MARK: Đổi tên tại chỗ

        private func beginRename(path: String) {
            guard let table, let row = rowByPath[path], row < items.count else { return }
            let col = table.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
            guard col >= 0 else { return }
            let item = items[row]
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            guard let cell = table.view(atColumn: col, row: row, makeIfNecessary: true) as? ListCell,
                  let field = cell.textField else { return }
            field.isEditable = true
            field.delegate = self
            editing = (path, item.name)
            cancelled = false
            guard table.window?.makeFirstResponder(field) == true else {
                editing = nil; field.isEditable = false; return
            }
            field.currentEditor()?.selectedRange = NSRange(
                location: 0, length: FileNameSelection.length(of: item.name, stripExtension: !item.isNavigableFolder))
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, let e = editing else { return }
            editing = nil
            field.isEditable = false
            field.delegate = nil
            let text = field.stringValue
            if cancelled || text == e.original || !model.commitRename(path: e.path, to: text) {
                field.stringValue = e.original
            }
            cancelled = false
            DispatchQueue.main.async { [weak self] in
                guard let self, let table else { return }
                table.window?.makeFirstResponder(table)
                // Bù lần nạp lại đã hoãn trong lúc gõ.
                sync(generation: model.generation, resetToken: model.resetToken, revealToken: model.revealToken,
                     sort: model.prefs.sort, pathEditing: model.pathEditing, renameToken: model.renameToken,
                     showWhere: model.inSubfolderSearch)
            }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            guard commandSelector == #selector(NSResponder.cancelOperation(_:)) else { return false }
            cancelled = true
            table?.window?.makeFirstResponder(table)
            return true
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, row < items.count else { return nil }
            let item = items[row]
            let id = tableColumn.identifier
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? ListCell)
                ?? Self.makeCell(id, hasIcon: id.rawValue == "name")
            cell.requester = thumbs
            let text: String
            switch id.rawValue {
            case "name":
                text = item.name
                cell.representedPath = item.url.path
                let scale = tableView.window?.backingScaleFactor ?? 2
                if let img = thumbs.cached(item, points: Self.iconPoints, scale: scale) {
                    thumbs.cancel(cell)
                    cell.imageView?.image = img
                } else {
                    cell.imageView?.image = IconCache.shared.icon(for: item, size: Self.iconPoints)
                    let path = item.url.path
                    thumbs.load(for: cell, item: item, points: Self.iconPoints, scale: scale) { [weak cell, weak self] img in
                        // Cell có thể đã được tái dùng cho dòng khác.
                        guard let cell, let self, self.rowByPath[path] != nil, cell.representedPath == path else { return }
                        cell.imageView?.image = img
                    }
                }
            case "where": text = model.searchWhere(for: item)
            case "modified": text = item.modified.map { Self.dateFormatter().string(from: $0) } ?? "--"
            case "size":
                if item.isDirectory, !item.isSymlink, !item.isAlias {
                    // Kết quả Subfolders không tự tính cỡ thư mục.
                    text = model.folderSizes.info(for: item)?.size.map { fmtBytes($0) } ?? (model.inSubfolderSearch ? "--" : "…")
                } else {
                    text = item.size.map { fmtBytes($0) } ?? "--"
                }
            default: text = item.kindDescription
            }
            cell.textField?.stringValue = text
            cell.alphaValue = item.isHidden ? 0.6 : 1
            return cell
        }

        private static func makeCell(_ id: NSUserInterfaceItemIdentifier, hasIcon: Bool) -> ListCell {
            let cell = ListCell()
            cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingMiddle
            label.cell?.usesSingleLineMode = true
            cell.textField = label
            cell.addSubview(label)
            if hasIcon {
                let icon = NSImageView()
                icon.translatesAutoresizingMaskIntoConstraints = false
                cell.imageView = icon
                cell.addSubview(icon)
                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                    icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    icon.widthAnchor.constraint(equalToConstant: iconPoints),
                    icon.heightAnchor.constraint(equalToConstant: iconPoints),
                    label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                ])
            } else {
                label.textColor = .secondaryLabelColor
                label.lineBreakMode = id.rawValue == "where" ? .byTruncatingMiddle : .byTruncatingTail
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2).isActive = true
                if id.rawValue == "size" { label.alignment = .right }
            }
            NSLayoutConstraint.activate([
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }

        private static var formatter: (Lang, DateFormatter)?
        private static func dateFormatter() -> DateFormatter {
            if let f = formatter, f.0 == Loc.lang { return f.1 }
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            f.locale = Loc.lang == .vi ? Locale(identifier: "vi_VN") : Locale(identifier: "en_US")
            formatter = (Loc.lang, f)
            return f
        }

        // MARK: Kéo thả

        /// Không bắt đầu kéo khi đang đổi tên; chọn nhiều thì AppKit kéo cả các hàng đang chọn.
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard editing == nil, row < items.count else { return nil }
            return items[row].url as NSURL
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                       proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
            let sources = BrowserModel.fileURLs(from: info.draggingPasteboard)
            var dest = model.folder
            var onBackground = false
            if op == .on, row >= 0, row < items.count, items[row].isNavigableFolder,
               !sources.contains(where: { $0.standardizedFileURL.path == items[row].url.standardizedFileURL.path }) {
                dest = items[row].url
            } else {
                // Thả vào chỗ khác → cả bảng = thư mục đang xem (trừ khi đang xem kết quả tìm Subfolders).
                tableView.setDropRow(-1, dropOperation: .on)
                onBackground = true
            }
            guard model.pinax == nil, !onBackground || model.backgroundDropAllowed,
                  let kind = model.dropKind(sources: sources, destination: dest, mask: info.draggingSourceOperationMask)
            else { return [] }
            return kind == .move ? .move : .copy
        }

        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo,
                       row: Int, dropOperation op: NSTableView.DropOperation) -> Bool {
            let sources = BrowserModel.fileURLs(from: info.draggingPasteboard)
            var dest = model.folder
            var onBackground = true
            if op == .on, row >= 0, row < items.count, items[row].isNavigableFolder { dest = items[row].url; onBackground = false }
            guard !onBackground || model.backgroundDropAllowed,
                  let kind = model.dropKind(sources: sources, destination: dest, mask: info.draggingSourceOperationMask)
            else { return false }
            model.performDrop(sources: sources, destination: dest, kind: kind)
            return true
        }

        // MARK: Delegate

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let table else { return }
            model.selection = Set(table.selectedRowIndexes.compactMap { $0 < items.count ? items[$0].url.path : nil })
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isUpdating, let d = tableView.sortDescriptors.first,
                  let key = d.key.flatMap(FileSort.Key.init(rawValue:)) else { return }
            model.prefs.sort.key = key
            model.prefs.sort.ascending = d.ascending
        }

        /// Type-to-select tích hợp sẵn của NSTableView cần chuỗi để so khớp.
        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            row < items.count ? items[row].name : nil
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let table, table.clickedRow >= 0, table.clickedRow < items.count else { return }
            let clicked = items[table.clickedRow]
            model.open(table.selectedRowIndexes.contains(table.clickedRow) ? model.selectedItems : [clicked])
        }
    }
}
