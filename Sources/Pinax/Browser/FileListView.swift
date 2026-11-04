import SwiftUI
import AppKit
import PinaxCore

/// NSTableView có chỗ gắn context menu (bước sau).
final class BrowserTableView: NSTableView {
    /// Extension point: bước D gắn menu chuột phải ở đây.
    var menuProvider: ((NSEvent) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider?(event) ?? super.menu(for: event) }
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

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let table = BrowserTableView()
        table.style = .fullWidth
        table.usesAlternatingRowBackgroundColors = true
        table.allowsMultipleSelection = true
        table.allowsColumnReordering = true
        table.allowsColumnResizing = true
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.rowSizeStyle = .default
        table.dataSource = c
        table.delegate = c
        table.target = c
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))

        func column(_ id: String, _ title: String, width: CGFloat, min: CGFloat, key: FileSort.Key) -> NSTableColumn {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id))
            col.title = title
            col.width = width
            col.minWidth = min
            col.sortDescriptorPrototype = NSSortDescriptor(key: key.rawValue, ascending: true)
            return col
        }
        table.addTableColumn(column("name", L("Name", "Tên"), width: 340, min: 160, key: .name))
        table.addTableColumn(column("modified", L("Date Modified", "Ngày sửa"), width: 200, min: 120, key: .modified))
        let sizeCol = column("size", L("Size", "Dung lượng"), width: 90, min: 60, key: .size)
        sizeCol.headerCell.alignment = .right
        table.addTableColumn(sizeCol)
        table.addTableColumn(column("kind", L("Kind", "Loại"), width: 150, min: 80, key: .kind))
        table.autosaveName = "pinax.browser.list.v2"
        table.autosaveTableColumns = true

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        c.table = table
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.model = model
        c.sync(generation: generation, resetToken: resetToken, revealToken: revealToken,
               sort: sort, pathEditing: pathEditing)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var model: BrowserModel
        weak var table: BrowserTableView?
        private var items: [FileItem] = []
        private var rowByPath: [String: Int] = [:]
        private var lastGeneration = -1, lastReset = -1, lastReveal = -1
        private var wasEditingPath = false
        private var didInitialFocus = false
        private var isUpdating = false

        init(model: BrowserModel) { self.model = model }

        func sync(generation: Int, resetToken: Int, revealToken: Int, sort: FileSort, pathEditing: Bool) {
            guard let table else { return }
            isUpdating = true
            defer { isUpdating = false }

            let desc = NSSortDescriptor(key: sort.key.rawValue, ascending: sort.ascending)
            if table.sortDescriptors.first.map({ $0.key != desc.key || $0.ascending != desc.ascending }) ?? true {
                table.sortDescriptors = [desc]
            }

            if generation != lastGeneration {
                lastGeneration = generation
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
                #if DEBUG
                if let start = model.navStart {
                    model.navStart = nil
                    let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                    FileHandle.standardError.write(Data(String(
                        format: "[Pinax perf] %d items: navigation start -> table reload %.1f ms\n", items.count, ms).utf8))
                }
                #endif
                if !didInitialFocus, !items.isEmpty, !pathEditing {
                    didInitialFocus = true
                    table.window?.makeFirstResponder(table)
                }
            }

            // Thoát ⌘L → trả focus cho bảng để type-to-select / phím mũi tên chạy tiếp.
            if wasEditingPath, !pathEditing { table.window?.makeFirstResponder(table) }
            wasEditingPath = pathEditing
        }

        // MARK: Data source

        func numberOfRows(in tableView: NSTableView) -> Int { items.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let tableColumn, row < items.count else { return nil }
            let item = items[row]
            let id = tableColumn.identifier
            let cell = (tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView)
                ?? Self.makeCell(id, hasIcon: id.rawValue == "name")
            let text: String
            switch id.rawValue {
            case "name":
                text = item.name
                cell.imageView?.image = IconCache.shared.icon(for: item)
            case "modified": text = item.modified.map { Self.dateFormatter().string(from: $0) } ?? "--"
            case "size": text = item.size.map { fmtBytes($0) } ?? "--"
            default: text = item.kindDescription
            }
            cell.textField?.stringValue = text
            cell.alphaValue = item.isHidden ? 0.6 : 1
            return cell
        }

        private static func makeCell(_ id: NSUserInterfaceItemIdentifier, hasIcon: Bool) -> NSTableCellView {
            let cell = NSTableCellView()
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
                    icon.widthAnchor.constraint(equalToConstant: 16),
                    icon.heightAnchor.constraint(equalToConstant: 16),
                    label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
                ])
            } else {
                label.textColor = .secondaryLabelColor
                label.lineBreakMode = .byTruncatingTail
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
