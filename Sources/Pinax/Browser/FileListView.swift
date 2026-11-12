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
        if flags.isEmpty, event.keyCode == 36 || event.keyCode == 76 {
            if model.canRenameSelection {
                model.beginRenameSelection()
                return true
            }
            if model.canBatchRename {
                model.beginBatchRename()
                return true
            }
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
    /// Dòng tiêu đề nhóm: chuột phải coi như chỗ trống.
    var isHeaderRow: ((Int) -> Bool)?

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
    @objc func cut(_ sender: Any?) { model?.cutSelectionToPasteboard() }
    @objc func copy(_ sender: Any?) { model?.copySelectionToPasteboard() }
    @objc func paste(_ sender: Any?) { model?.pasteFromPasteboard(move: false) }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(cut(_:)): model?.canCutSelection ?? false
        case #selector(copy(_:)): model?.canCopySelection ?? false
        case #selector(paste(_:)): model?.canPaste ?? false
        default: true
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        model?.onActivate?()
        // Như Finder: chuột phải vào mục chưa chọn → chọn riêng mục đó; vào chỗ trống → bỏ chọn.
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0, isHeaderRow?(row) != true {
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
    /// Chấm tag (chỉ ô Tên); đứng ngay sau chữ, sát mép phải nếu tên bị cắt.
    let tagDots = TagDotsView()
    private var dotsGap: NSLayoutConstraint?
    private var editFill: NSLayoutConstraint?

    override func prepareForReuse() {
        super.prepareForReuse()
        MainActor.assumeIsolated { requester?.cancel(self) }
        representedPath = nil
        setTags([])
        setRenaming(false)
    }

    /// Ô Tên: thay ràng buộc phải của chữ bằng "chữ co theo nội dung + chấm tag".
    func installTagDots() {
        guard let label = textField else { return }
        tagDots.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tagDots)
        // Chữ không giãn hết ô: ôm nội dung, nhường chỗ cho chấm (chấm không bao giờ bị nén).
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let gap = tagDots.leadingAnchor.constraint(equalTo: label.trailingAnchor, constant: 0)
        dotsGap = gap
        let fill = label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4)
        fill.isActive = false
        editFill = fill
        NSLayoutConstraint.activate([
            gap,
            tagDots.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            tagDots.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func setTags(_ tags: [String]) {
        tagDots.tags = tags
        dotsGap?.constant = tagDots.count == 0 ? 0 : 4
    }

    /// Đang đổi tên tại chỗ: ô nhập chiếm hết chiều ngang, chấm ẩn.
    func setRenaming(_ on: Bool) {
        editFill?.isActive = on
        tagDots.collapsed = on
        dotsGap?.constant = tagDots.count == 0 ? 0 : 4
    }
}

/// Ô tiêu đề nhóm: "Hình ảnh  12".
final class GroupHeaderCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("groupHeader")

    override init(frame: NSRect) {
        super.init(frame: frame)
        identifier = Self.identifier
        let label = NSTextField(labelWithString: "")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.lineBreakMode = .byTruncatingTail
        textField = label
        addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    func configure(title: String, count: Int) {
        let s = NSMutableAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.labelColor])
        s.append(NSAttributedString(string: "  \(count)", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.secondaryLabelColor]))
        textField?.attributedStringValue = s
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
        table.floatsGroupRows = true
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
            // Hai khung: mỗi khung chỉ ~380 pt, tổng min của bản một khung (≈ 390 pt) không vừa → cột Loại bị cắt.
            col.minWidth = dual ? Swift.min(min, 56) : min
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
        table.isHeaderRow = { [weak c] row in c?.item(atRow: row) == nil }
        table.menuProvider = { [weak c] _ in c.map { BrowserMenu.make(model: $0.model) } }
        table.keyHandler = { [weak c] event in
            guard let c else { return false }
            return BrowserKeys.handle(event, model: c.model)
        }
        c.model.folderSizes.observe(c) { [weak c] path in c?.sizeResolved(path) }
        c.model.tags.observe(c) { [weak c] path in c?.tagsResolved(path) }
        // Khung hẹp lại (mở preview, thu cửa sổ) mà NSTableView không tự co cột Tên → các cột sau bị đẩy ra ngoài.
        // Một khung: cột Tên lấp phần còn lại. Hai khung: co đều mọi cột khi tổng bề rộng lệch khung.
        scroll.contentView.postsFrameChangedNotifications = true
        c.frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: scroll.contentView, queue: .main) { [weak c] _ in
            MainActor.assumeIsolated { dual ? c?.fitColumnsUniformly() : c?.fitNameColumn() }
        }
        if !dual { DispatchQueue.main.async { [weak c] in c?.fitNameColumn() } }
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.model.folderSizes.stopObserving(coordinator)
        coordinator.model.tags.stopObserving(coordinator)
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
        var frameObserver: NSObjectProtocol?

        /// Cột Tên lấp phần còn lại của khung: các cột khác giữ nguyên bề rộng.
        func fitNameColumn() {
            guard let table, let clip = table.enclosingScrollView?.contentView,
                  let name = table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("name")) else { return }
            let visible = table.tableColumns.filter { !$0.isHidden }
            let others = visible.filter { $0 !== name }.reduce(CGFloat(0)) { $0 + $1.width }
            let spacing = table.intercellSpacing.width * CGFloat(visible.count)
            let target = max(name.minWidth, clip.bounds.width - others - spacing)
            if abs(name.width - target) > 0.5 { name.width = target }
        }

        /// Hai khung: sizeToFit khi bề rộng khung lệch tổng các cột > 1 pt (sizeToFit đặt đúng bề rộng nên không lặp vô hạn).
        func fitColumnsUniformly() {
            guard let table, let clip = table.enclosingScrollView?.contentView else { return }
            let visible = table.tableColumns.filter { !$0.isHidden }
            guard !visible.isEmpty else { return }
            let total = visible.reduce(CGFloat(0)) { $0 + $1.width } + table.intercellSpacing.width * CGFloat(visible.count)
            if abs(clip.bounds.width - total) > 1 { table.sizeToFit() }
        }
        private var items: [FileItem] = []
        /// Dòng bảng: tiêu đề nhóm hoặc chỉ số trong `items`. Không nhóm → toàn `.item`.
        private enum Row { case header(BrowserModel.GroupSpan), item(Int) }
        private var rows: [Row] = []

        /// Mục ở dòng bảng; nil với tiêu đề nhóm hoặc ngoài phạm vi.
        func item(atRow row: Int) -> FileItem? {
            guard row >= 0, row < rows.count, case .item(let i) = rows[row], i < items.count else { return nil }
            return items[i]
        }

        private static func buildRows(count: Int, groups: [BrowserModel.GroupSpan]) -> [Row] {
            guard !groups.isEmpty else { return (0..<count).map { .item($0) } }
            var out: [Row] = []
            out.reserveCapacity(count + groups.count)
            for g in groups {
                out.append(.header(g))
                for i in g.start..<g.start + g.count { out.append(.item(i)) }
            }
            return out
        }
        /// path -> chỉ số dòng bảng (đã tính dòng tiêu đề).
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

        private var cutObserver: NSObjectProtocol?

        init(model: BrowserModel) {
            self.model = model
            super.init()
            // ⌘X / dán / chép → vẽ lại các dòng đang hiện để mục bị cắt mờ đi hoặc rõ lại.
            cutObserver = NotificationCenter.default.addObserver(forName: ClipboardCut.didChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshCutState() }
            }
        }

        isolated deinit {
            if let cutObserver { NotificationCenter.default.removeObserver(cutObserver) }
            if let frameObserver { NotificationCenter.default.removeObserver(frameObserver) }
        }

        private func refreshCutState() {
            guard let table, editing == nil else { return }
            let rows = table.rows(in: table.visibleRect)
            guard rows.length > 0 else { return }
            table.reloadData(forRowIndexes: IndexSet(integersIn: rows.location..<rows.location + rows.length),
                             columnIndexes: IndexSet(integersIn: 0..<table.numberOfColumns))
        }

        /// Một thư mục vừa tính xong → vẽ lại ô Size của đúng dòng đó.
        func sizeResolved(_ path: String) {
            guard let table, let row = rowByPath[path] else { return }
            let col = table.column(withIdentifier: NSUserInterfaceItemIdentifier("size"))
            guard col >= 0 else { return }
            table.reloadData(forRowIndexes: IndexSet(integer: row), columnIndexes: IndexSet(integer: col))
        }

        /// Tag của một mục vừa nạp xong → cập nhật chấm của đúng ô Tên đang hiện (không reload, không đụng ô đang đổi tên).
        func tagsResolved(_ path: String) {
            guard let table, editing?.path != path, let row = rowByPath[path] else { return }
            let col = table.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
            guard col >= 0, let cell = table.view(atColumn: col, row: row, makeIfNecessary: false) as? ListCell,
                  cell.representedPath == path else { return }
            cell.setTags(model.tags.tags(for: path) ?? [])
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
                col.isHidden = !showWhere
                if name != nil, table.columnAutoresizingStyle == .firstColumnOnlyAutoresizingStyle { fitNameColumn() }
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
                rows = Self.buildRows(count: items.count, groups: model.groups)
                var byPath: [String: Int] = [:]
                byPath.reserveCapacity(items.count)
                for (r, row) in rows.enumerated() {
                    if case .item(let i) = row, byPath[items[i].url.path] == nil { byPath[items[i].url.path] = r }
                }
                rowByPath = byPath
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
            guard let table, let row = rowByPath[path], let item = item(atRow: row) else { return }
            let col = table.column(withIdentifier: NSUserInterfaceItemIdentifier("name"))
            guard col >= 0 else { return }
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            guard let cell = table.view(atColumn: col, row: row, makeIfNecessary: true) as? ListCell,
                  let field = cell.textField else { return }
            field.isEditable = true
            field.delegate = self
            cell.setRenaming(true)
            editing = (path, item.name)
            cancelled = false
            guard table.window?.makeFirstResponder(field) == true else {
                editing = nil; field.isEditable = false; cell.setRenaming(false); return
            }
            field.currentEditor()?.selectedRange = NSRange(
                location: 0, length: FileNameSelection.length(of: item.name, stripExtension: !item.isNavigableFolder))
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField, let e = editing else { return }
            editing = nil
            field.isEditable = false
            field.delegate = nil
            if let cell = field.superview as? ListCell { cell.setRenaming(false) }
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

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            row >= 0 && row < rows.count && item(atRow: row) == nil
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { item(atRow: row) != nil }

        func tableView(_ tableView: NSTableView, selectionIndexesForProposedSelection proposed: IndexSet) -> IndexSet {
            proposed.filter { item(atRow: $0) != nil }.reduce(into: IndexSet()) { $0.insert($1) }
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            if row >= 0, row < rows.count, case .header(let g) = rows[row] {
                let cell = (tableView.makeView(withIdentifier: GroupHeaderCell.identifier, owner: nil) as? GroupHeaderCell)
                    ?? GroupHeaderCell(frame: .zero)
                cell.configure(title: g.title, count: g.count)
                return cell
            }
            guard let tableColumn, let item = item(atRow: row) else { return nil }
            let id = tableColumn.identifier
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? ListCell)
                ?? Self.makeCell(id, hasIcon: id.rawValue == "name")
            cell.requester = thumbs
            let text: String
            switch id.rawValue {
            case "name":
                text = item.name
                cell.representedPath = item.url.path
                cell.setTags(model.tags.tags(for: item.url.path) ?? [])
                model.tags.request([item.url.path])
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
            cell.alphaValue = (item.isHidden ? 0.6 : 1) * ClipboardCut.alpha(item.url.path)
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
                cell.installTagDots()
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
            // Ô Tên: chữ ôm nội dung (≤ mép phải) để chấm tag đứng ngay sau; ô khác giãn hết.
            if hasIcon {
                label.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4).isActive = true
            } else {
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4).isActive = true
            }
            label.centerYAnchor.constraint(equalTo: cell.centerYAnchor).isActive = true
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
            guard editing == nil, let item = item(atRow: row) else { return nil }
            return item.url as NSURL
        }

        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo,
                       proposedRow row: Int, proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
            let sources = BrowserModel.fileURLs(from: info.draggingPasteboard)
            var dest = model.folder
            var onBackground = false
            if op == .on, let target = item(atRow: row), target.isNavigableFolder,
               !sources.contains(where: { $0.standardizedFileURL.path == target.url.standardizedFileURL.path }) {
                dest = target.url
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
            if op == .on, let target = item(atRow: row), target.isNavigableFolder { dest = target.url; onBackground = false }
            guard !onBackground || model.backgroundDropAllowed,
                  let kind = model.dropKind(sources: sources, destination: dest, mask: info.draggingSourceOperationMask)
            else { return false }
            model.performDrop(sources: sources, destination: dest, kind: kind)
            return true
        }

        // MARK: Delegate

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isUpdating, let table else { return }
            model.selection = Set(table.selectedRowIndexes.compactMap { item(atRow: $0)?.url.path })
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            guard !isUpdating, let d = tableView.sortDescriptors.first,
                  let key = d.key.flatMap(FileSort.Key.init(rawValue:)) else { return }
            model.prefs.sort.key = key
            model.prefs.sort.ascending = d.ascending
        }

        /// Type-to-select tích hợp sẵn của NSTableView cần chuỗi để so khớp.
        func tableView(_ tableView: NSTableView, typeSelectStringFor tableColumn: NSTableColumn?, row: Int) -> String? {
            item(atRow: row)?.name
        }

        @objc func doubleClicked(_ sender: Any?) {
            guard let table, let clicked = item(atRow: table.clickedRow) else { return }
            model.open(table.selectedRowIndexes.contains(table.clickedRow) ? model.selectedItems : [clicked])
        }
    }
}
