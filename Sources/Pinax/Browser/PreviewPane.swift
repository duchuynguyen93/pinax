import SwiftUI
import AppKit
import Quartz
import UniformTypeIdentifiers
import Observation
import PinaxCore

/// Bấm một lần khi một thư mục tính xong dung lượng (FolderSizeStore chỉ có callback, không phải Observable).
@MainActor @Observable
private final class SizeTicker { var n = 0 }

/// Khung xem trước bên phải: theo vùng chọn của pane (không chọn gì → thư mục đang xem).
struct PreviewPane: View {
    let model: BrowserModel

    private enum Loaded {
        case file(FileItem)
        case folder(FileItem, children: [FileItem], total: Int)
        case multi([FileItem])
    }

    private struct Sub { var items: [FileItem]; var total: Int }

    private struct LoadKey: Hashable {
        var pane: ObjectIdentifier
        var selection: Set<String>
        var folder: String
        var generation: Int
        var hidden: Bool
    }

    private static let childLimit = 30
    private static let subLimit = 20
    private static let bigFile: Int64 = 2 << 30

    @State private var loaded: Loaded?
    @State private var expanded: [String: Sub] = [:]
    @State private var ticker = SizeTicker()

    private var key: LoadKey {
        LoadKey(pane: ObjectIdentifier(model), selection: model.selection, folder: model.folder.path,
                generation: model.generation, hidden: model.prefs.showHidden)
    }

    var body: some View {
        Group {
            switch loaded {
            case .file(let item): fileView(item)
            case .folder(let item, let children, let total): folderView(item, children: children, total: total)
            case .multi(let items): multiView(items)
            case nil: Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: key) { await load() }
        .task(id: ObjectIdentifier(model)) {
            model.folderSizes.observe(ticker) { [ticker] _ in ticker.n += 1 }
        }
        .onDisappear { model.folderSizes.stopObserving(ticker) }
    }

    // MARK: Nạp

    private func load() async {
        try? await Task.sleep(for: .milliseconds(120))
        if Task.isCancelled { return }
        let selected = model.selectedItems
        let folderURL = model.folder
        let hidden = model.prefs.showHidden
        let result: Loaded?
        switch selected.count {
        case 0:
            result = await folderContent(url: folderURL, fallback: nil, hidden: hidden)
        case 1:
            let sel = selected[0]
            if sel.isNavigableFolder {
                result = await folderContent(url: sel.url, fallback: sel, hidden: hidden)
            } else {
                result = .file(await Task.detached { Self.detailed(sel) }.value)
            }
        default:
            result = .multi(selected)
            model.folderSizes.request(selected)
        }
        if Task.isCancelled { return }
        if let result {
            if case .folder(let it, _, _) = result { model.folderSizes.request([it]) }
            expanded = [:]
            loaded = result
        }
    }

    private func folderContent(url: URL, fallback: FileItem?, hidden: Bool) async -> Loaded? {
        guard let item = await Task.detached(operation: { () -> FileItem? in
            guard let base = fallback ?? FileItem.make(url: url) else { return nil }
            return Self.detailed(base)
        }).value else { return nil }
        let list = (try? await DirectoryLister.list(url, showHidden: hidden)) ?? []
        if Task.isCancelled { return nil }
        let sorted = Self.sortedChildren(list)
        return .folder(item, children: Array(sorted.prefix(Self.childLimit)), total: sorted.count)
    }

    /// Bổ sung tag (loadingDetails) + ngày tạo, ngày sửa mới nhất. Gọi ngoài main.
    nonisolated private static func detailed(_ item: FileItem) -> FileItem {
        let d = item.loadingDetails()
        var fresh = item.url
        fresh.removeAllCachedResourceValues()
        let v = try? fresh.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        return FileItem(
            url: d.url, name: d.name, isDirectory: d.isDirectory, isPackage: d.isPackage, isHidden: d.isHidden,
            isSymlink: d.isSymlink, isAlias: d.isAlias, size: d.size, modified: v?.contentModificationDate ?? d.modified,
            created: v?.creationDate, kindDescription: d.kindDescription, contentType: d.contentType,
            tagNames: d.tagNames, ubiquitousStatus: d.ubiquitousStatus)
    }

    private static func sortedChildren(_ list: [FileItem]) -> [FileItem] {
        list.sorted {
            if $0.isNavigableFolder != $1.isNavigableFolder { return $0.isNavigableFolder }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func toggle(_ item: FileItem) {
        let path = item.url.path
        if expanded[path] != nil { expanded[path] = nil; return }
        let hidden = model.prefs.showHidden
        Task {
            let list = (try? await DirectoryLister.list(item.url, showHidden: hidden)) ?? []
            let sorted = Self.sortedChildren(list)
            expanded[path] = Sub(items: Array(sorted.prefix(Self.subLimit)), total: sorted.count)
        }
    }

    private func activate(_ item: FileItem) {
        if item.isNavigableFolder { model.navigate(to: item.url) } else { model.open([item]) }
    }

    // MARK: Một file

    private func previewable(_ item: FileItem) -> Bool {
        guard (item.size ?? 0) > Self.bigFile else { return true }
        let t = item.contentType
        return t?.conforms(to: .image) == true || t?.conforms(to: .movie) == true
    }

    private func fileView(_ item: FileItem) -> some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                Group {
                    if previewable(item) {
                        QuickLookPreview(url: item.url).id(item.url)
                    } else {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable().scaledToFit().frame(width: 128, height: 128).padding(.top, 24)
                    }
                }
                .frame(height: previewable(item) ? geo.size.height * 0.55 : 160)
                Divider()
                ScrollView { metadata(item, isFolder: false).padding(12) }
            }
        }
    }

    // MARK: Một thư mục

    private struct TreeRow: Identifiable {
        let item: FileItem
        let depth: Int
        var id: String { item.url.path }
    }

    private func folderView(_ item: FileItem, children: [FileItem], total: Int) -> some View {
        var rows: [TreeRow] = []
        var extras: [String: Int] = [:]
        for c in children {
            rows.append(TreeRow(item: c, depth: 0))
            if let sub = expanded[c.url.path] {
                rows += sub.items.map { TreeRow(item: $0, depth: 1) }
                if sub.total > sub.items.count { extras[c.url.path] = sub.total - sub.items.count }
            }
        }
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable().scaledToFit().frame(width: 96, height: 96)
                    .frame(maxWidth: .infinity)
                metadata(item, isFolder: true)
                Divider()
                Text(L("Contents", "Nội dung")).font(.caption).foregroundStyle(.secondary)
                if rows.isEmpty {
                    Text(L("This folder is empty", "Thư mục trống")).foregroundStyle(.secondary)
                }
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        treeRow(row)
                        if let more = extras[row.id] {
                            Text(L("+ \(more) more", "+ \(more) mục nữa"))
                                .font(.caption).foregroundStyle(.secondary).padding(.leading, 40).padding(.vertical, 2)
                        }
                    }
                }
                if total > children.count {
                    Text(L("+ \(total - children.count) more", "+ \(total - children.count) mục nữa"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    private func treeRow(_ row: TreeRow) -> some View {
        HStack(spacing: 4) {
            if row.item.isNavigableFolder && row.depth == 0 {
                Button { toggle(row.item) } label: {
                    Image(systemName: expanded[row.id] != nil ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).frame(width: 14)
                }
                .buttonStyle(.plain)
            } else {
                Color.clear.frame(width: 14)
            }
            Image(nsImage: IconCache.shared.icon(for: row.item)).frame(width: 16, height: 16)
            Text(row.item.name).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 16)
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { activate(row.item) }
    }

    // MARK: Nhiều mục

    private func multiView(_ items: [FileItem]) -> some View {
        _ = ticker.n
        var total: Int64 = 0
        var pending = false
        for it in items {
            if it.isDirectory {
                if let s = model.folderSizes.info(for: it)?.size { total += s } else { pending = true }
            } else {
                total += it.size ?? 0
            }
        }
        return VStack(spacing: 12) {
            ZStack {
                ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.offset) { i, it in
                    Image(nsImage: IconCache.shared.icon(for: it, size: 80))
                        .frame(width: 80, height: 80)
                        .offset(x: CGFloat(i) * 14, y: CGFloat(i) * 8)
                }
            }
            .frame(width: 120, height: 100).padding(.top, 24)
            Text(L("\(items.count) items", "\(items.count) mục")).font(.headline)
            Text(Self.bytes(total) + (pending ? "…" : "")).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Thông tin

    private static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    private func metadata(_ item: FileItem, isFolder: Bool) -> some View {
        _ = ticker.n
        let parent = item.url.deletingLastPathComponent()
        var sizeText = "…"
        if isFolder {
            model.folderSizes.request([item])
            if let info = model.folderSizes.info(for: item), let size = info.size {
                sizeText = Self.bytes(size)
                if let c = info.count { sizeText = L("\(c) items, ", "\(c) mục, ") + sizeText }
            }
        } else {
            sizeText = item.size.map(Self.bytes) ?? "—"
        }
        return VStack(alignment: .leading, spacing: 6) {
            Text(item.name).font(.headline).textSelection(.enabled)
            row(L("Kind", "Loại"), item.kindDescription)
            row(L("Size", "Dung lượng"), sizeText)
            if let d = item.created { row(L("Created", "Ngày tạo"), d.formatted(date: .abbreviated, time: .shortened)) }
            if let d = item.modified { row(L("Modified", "Ngày sửa"), d.formatted(date: .abbreviated, time: .shortened)) }
            if !item.tagNames.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    label(L("Tags", "Thẻ"))
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(item.tagNames, id: \.self) { name in
                            HStack(spacing: 5) {
                                Circle().fill(Self.tagColor(name)).frame(width: 9, height: 9)
                                Text(Self.cleanTag(name))
                            }
                        }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline) {
                label(L("Where", "Vị trí"))
                Button { model.navigate(to: parent, select: item.url.path) } label: {
                    Text(parent.path).multilineTextAlignment(.leading).foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
                .help(L("Show in this window", "Hiện trong cửa sổ này"))
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ s: String) -> some View {
        Text(s).foregroundStyle(.secondary).frame(width: 78, alignment: .trailing)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            label(title)
            Text(value).textSelection(.enabled)
        }
    }

    private static func cleanTag(_ name: String) -> String {
        name.split(separator: "\n").first.map(String.init) ?? name
    }

    /// Tag chuẩn của Finder có màu; tag tự đặt không rõ màu → xám.
    private static func tagColor(_ name: String) -> Color {
        let ws = NSWorkspace.shared
        if let i = ws.fileLabels.firstIndex(of: cleanTag(name)), i > 0, i < ws.fileLabelColors.count {
            return Color(nsColor: ws.fileLabelColors[i])
        }
        return .gray
    }
}

/// `QLPreviewView` kiểu compact; bọc lại bằng `.id(url)` để mỗi file một view mới.
private struct QuickLookPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let v = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView()
        v.previewItem = url as NSURL
        return v
    }

    func updateNSView(_ v: QLPreviewView, context: Context) {}

    static func dismantleNSView(_ v: QLPreviewView, coordinator: ()) { v.close() }
}
