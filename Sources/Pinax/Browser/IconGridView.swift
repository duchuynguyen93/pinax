import SwiftUI
import AppKit
import PinaxCore

/// NSCollectionView có double-click, phím tắt trình duyệt, type-to-select và chỗ gắn context menu.
final class BrowserCollectionView: NSCollectionView {
    /// Extension point: bước D gắn menu chuột phải ở đây.
    var menuProvider: ((NSEvent) -> NSMenu?)?
    var keyHandler: ((NSEvent) -> Bool)?
    var onOpen: (() -> Void)?
    var onTypeSelect: ((String) -> Void)?
    private var typed = ""
    private var lastTyped = Date.distantPast

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        if event.clickCount == 2, indexPathForItem(at: convert(event.locationInWindow, from: nil)) != nil { onOpen?() }
    }

    override func keyDown(with event: NSEvent) {
        if keyHandler?(event) == true { return }
        let flags = event.modifierFlags.intersection([.command, .control, .option])
        if flags.isEmpty, let chars = event.characters, chars.count == 1,
           let scalar = chars.unicodeScalars.first, !CharacterSet.controlCharacters.contains(scalar),
           !(0xF700...0xF8FF).contains(scalar.value) {
            let now = Date()
            if now.timeIntervalSince(lastTyped) > 1 { typed = "" }
            lastTyped = now
            typed += chars
            onTypeSelect?(typed)
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // Chuột phải vào mục chưa chọn → chọn riêng mục đó (như Finder).
        if let ip = indexPathForItem(at: convert(event.locationInWindow, from: nil)), !selectionIndexPaths.contains(ip) {
            selectionIndexPaths = [ip]
            delegate?.collectionView?(self, didSelectItemsAt: [ip])
        }
        return menuProvider?(event) ?? super.menu(for: event)
    }
}

/// View của một ô: icon/thumbnail, tên (tối đa 2 dòng), dòng phụ (thư mục: "N mục · dung lượng").
final class IconItemView: NSView {
    let imageView = NSImageView()
    let title = NSTextField(wrappingLabelWithString: "")
    let subtitle = NSTextField(labelWithString: "")
    var iconPoints: CGFloat = 80 { didSet { needsLayout = true } }
    var selected = false { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        title.alignment = .center
        title.maximumNumberOfLines = 2
        title.lineBreakMode = .byTruncatingMiddle
        title.font = .systemFont(ofSize: 12)
        title.cell?.truncatesLastVisibleLine = true
        subtitle.alignment = .center
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        for v in [imageView, title, subtitle] { addSubview(v) }
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let w = bounds.width
        imageView.frame = NSRect(x: (w - iconPoints) / 2, y: 4, width: iconPoints, height: iconPoints)
        title.frame = NSRect(x: 4, y: iconPoints + 8, width: w - 8, height: 30)
        subtitle.frame = NSRect(x: 4, y: iconPoints + 38, width: w - 8, height: 14)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard selected else { return }
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.28).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8).fill()
    }
}

final class IconItem: NSCollectionViewItem {
    weak var requester: ThumbnailRequester?
    var representedPath: String?
    var itemView: IconItemView { view as! IconItemView }

    override func loadView() { view = IconItemView(frame: .zero) }

    override var isSelected: Bool {
        didSet { itemView.selected = isSelected }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        MainActor.assumeIsolated { requester?.cancel(self) }
        representedPath = nil
    }
}

/// Icon view bằng NSCollectionView (không dùng LazyVGrid).
struct IconGridView: NSViewRepresentable {
    let model: BrowserModel
    let generation: Int
    let resetToken: Int
    let revealToken: Int
    let iconSize: IconSize
    let pathEditing: Bool

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> NSScrollView {
        let c = context.coordinator
        let layout = NSCollectionViewFlowLayout()
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 8
        layout.sectionInset = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        layout.itemSize = NSSize(width: iconSize.cellWidth, height: iconSize.cellHeight)

        let collection = BrowserCollectionView()
        collection.collectionViewLayout = layout
        collection.isSelectable = true
        collection.allowsMultipleSelection = true
        collection.backgroundColors = [.clear]
        collection.dataSource = c
        collection.delegate = c
        collection.register(IconItem.self, forItemWithIdentifier: Coordinator.itemID)
        collection.keyHandler = { [weak c] e in c.map { BrowserKeys.handle(e, model: $0.model) } ?? false }
        collection.onOpen = { [weak c] in c?.model.openSelection() }
        collection.onTypeSelect = { [weak c] s in c?.typeSelect(s) }

        let scroll = NSScrollView()
        scroll.documentView = collection
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        c.collection = collection
        c.model.folderSizes.observe(c) { [weak c] path in c?.sizeResolved(path) }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.model = model
        c.sync(generation: generation, resetToken: resetToken, revealToken: revealToken,
               iconSize: iconSize, pathEditing: pathEditing)
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        coordinator.model.folderSizes.stopObserving(coordinator)
        coordinator.thumbs.cancelAll()
    }

    @MainActor
    final class Coordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegateFlowLayout {
        static let itemID = NSUserInterfaceItemIdentifier("pinax.icon")
        var model: BrowserModel
        weak var collection: BrowserCollectionView?
        let thumbs = ThumbnailRequester()
        private var items: [FileItem] = []
        private var indexByPath: [String: Int] = [:]
        private var lastGeneration = -1, lastReset = -1, lastReveal = -1
        private var lastSize: IconSize?
        private var wasEditingPath = false
        private var didInitialFocus = false
        private var isUpdating = false

        init(model: BrowserModel) { self.model = model }

        func sync(generation: Int, resetToken: Int, revealToken: Int, iconSize: IconSize, pathEditing: Bool) {
            guard let collection else { return }
            isUpdating = true
            defer { isUpdating = false }

            var needsReload = false
            if iconSize != lastSize {
                lastSize = iconSize
                if let flow = collection.collectionViewLayout as? NSCollectionViewFlowLayout {
                    flow.itemSize = NSSize(width: iconSize.cellWidth, height: iconSize.cellHeight)
                    flow.invalidateLayout()
                }
                thumbs.cancelAll()
                needsReload = true
            }
            if generation != lastGeneration {
                lastGeneration = generation
                if resetToken != lastReset { thumbs.cancelAll() }
                items = model.items
                indexByPath = Dictionary(items.enumerated().map { ($1.url.path, $0) }, uniquingKeysWith: { a, _ in a })
                needsReload = true
            }
            guard needsReload else { finishFocus(pathEditing); return }

            collection.reloadData()
            let paths = Set(model.selection.compactMap { indexByPath[$0] }.map { IndexPath(item: $0, section: 0) })
            collection.selectionIndexPaths = paths
            if resetToken != lastReset {
                lastReset = resetToken
                if !items.isEmpty { collection.scrollToItems(at: [IndexPath(item: 0, section: 0)], scrollPosition: .top) }
            }
            if revealToken != lastReveal {
                lastReveal = revealToken
                if let first = paths.min() { collection.scrollToItems(at: [first], scrollPosition: .centeredVertically) }
            }
            #if DEBUG
            if let start = model.navStart {
                model.navStart = nil
                let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
                FileHandle.standardError.write(Data(String(
                    format: "[Pinax perf] %d items: navigation start -> icon view reload %.1f ms\n", items.count, ms).utf8))
            }
            #endif
            if !didInitialFocus, !items.isEmpty, !pathEditing {
                didInitialFocus = true
                collection.window?.makeFirstResponder(collection)
            }
            finishFocus(pathEditing)
        }

        private func finishFocus(_ pathEditing: Bool) {
            if wasEditingPath, !pathEditing { collection?.window?.makeFirstResponder(collection) }
            wasEditingPath = pathEditing
        }

        /// Thư mục tính xong → cập nhật dòng phụ của đúng ô đang hiện (không reload).
        func sizeResolved(_ path: String) {
            guard let collection, let i = indexByPath[path], i < items.count,
                  let cell = collection.item(at: IndexPath(item: i, section: 0)) as? IconItem else { return }
            cell.itemView.subtitle.stringValue = Self.subtitle(items[i], model: model)
        }

        static func subtitle(_ item: FileItem, model: BrowserModel) -> String {
            guard item.isDirectory, !item.isSymlink, !item.isAlias else { return "" }
            guard let info = model.folderSizes.info(for: item) else { return "…" }
            let size = info.size.map { fmtBytes($0) }
            if item.isPackage { return size ?? "" }
            return [info.count.map { itemsText($0) }, size].compactMap { $0 }.joined(separator: " · ")
        }

        func typeSelect(_ prefix: String) {
            guard let collection,
                  let i = items.firstIndex(where: { $0.name.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil })
            else { return }
            let ip = IndexPath(item: i, section: 0)
            collection.selectionIndexPaths = [ip]
            collection.scrollToItems(at: [ip], scrollPosition: .nearestHorizontalEdge)
            publishSelection()
        }

        private func publishSelection() {
            guard !isUpdating, let collection else { return }
            model.selection = Set(collection.selectionIndexPaths.compactMap { $0.item < items.count ? items[$0.item].url.path : nil })
        }

        // MARK: Data source

        func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let cell = collectionView.makeItem(withIdentifier: Self.itemID, for: indexPath) as! IconItem
            let item = items[indexPath.item]
            let size = model.iconSize
            let points = size.points
            let view = cell.itemView
            view.iconPoints = points
            view.title.stringValue = item.name
            view.subtitle.stringValue = Self.subtitle(item, model: model)
            view.alphaValue = item.isHidden ? 0.6 : 1
            view.selected = cell.isSelected
            cell.requester = thumbs
            cell.representedPath = item.url.path

            let scale = collectionView.window?.backingScaleFactor ?? 2
            if let img = thumbs.cached(item, points: points, scale: scale) {
                thumbs.cancel(cell)
                view.imageView.image = img
            } else {
                view.imageView.image = IconCache.shared.icon(for: item, size: points)
                let path = item.url.path
                thumbs.load(for: cell, item: item, points: points, scale: scale) { [weak cell] img in
                    guard let cell, cell.representedPath == path else { return }
                    cell.itemView.imageView.image = img
                }
            }
            return cell
        }

        // MARK: Delegate

        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { publishSelection() }
        func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { publishSelection() }
    }
}
