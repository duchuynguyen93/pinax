import SwiftUI
import AppKit
import QuickLook
import PinaxCore

/// Màu cho 8 con lớn nhất; phần còn lại xám.
private let spacePalette: [Color] = [.blue, .orange, .green, .purple, .pink, .teal, .yellow, .indigo]

extension SizeNode: Identifiable {
    public var id: ObjectIdentifier { ObjectIdentifier(self) }
}

private func nodeName(_ node: SizeNode) -> String {
    if node.kind == .others { return L("\(fmtCount(node.fileCount)) smaller files", "\(fmtCount(node.fileCount)) file nhỏ hơn") }
    guard node.parent == nil else { return node.name }
    let a = (node.name as NSString).abbreviatingWithTildeInPath
    return a.count > 28 ? (node.name as NSString).lastPathComponent : a
}

struct SpaceMapView: View {
    @Environment(SpaceMapModel.self) private var model
    let browser: BrowserModel
    @State private var quickLookURL: URL?

    var body: some View {
        @Bindable var model = model
        // Đọc treeVersion để vẽ lại khi cây (không observable) đổi.
        let _ = model.treeVersion
        VStack(spacing: 0) {
            topBar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: Binding(get: { model.confirmCandidates != nil },
                                    set: { if !$0 { model.cancelConfirm() } })) {
            let items = model.confirmCandidates ?? []
            ConfirmSheet(items: items, bytes: items.reduce(0) { $0 + $1.size }) {
                model.confirmTrash()
            } onCancel: {
                model.cancelConfirm()
            }
        }
        .onChange(of: model.current.map(ObjectIdentifier.init)) { quickLookURL = nil }
    }

    // MARK: Thanh trên

    private var topBar: some View {
        HStack(spacing: 8) {
            breadcrumb
            Spacer(minLength: 8)
            Button(L("Choose Folder…", "Chọn thư mục…")) { chooseFolder() }
            Button(L("Scan Home", "Quét Home")) { model.scanHome() }
            Button(L("Rescan", "Quét lại")) { model.rescan() }
                .disabled(model.result == nil || model.isScanning)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var breadcrumb: some View {
        let chain = model.chain
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(chain.enumerated()), id: \.offset) { i, node in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    if i == chain.count - 1 {
                        Text(nodeName(node)).fontWeight(.semibold).lineLimit(1)
                    } else {
                        Button(nodeName(node)) { model.jump(to: node) }
                            .buttonStyle(.link).lineLimit(1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = L("Scan", "Quét")
        if let root = model.scanRoot { panel.directoryURL = root }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.scan(url)
    }

    // MARK: Nội dung

    @ViewBuilder private var content: some View {
        switch model.state {
        case .scanning(let p):
            ScanningPane(progress: p)
        case .failed(let message):
            ContentUnavailableView {
                Label(L("Scan failed", "Quét không thành công"), systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button(L("Try Again", "Thử lại")) { model.rescan() }
            }
        case .idle, .done:
            if let current = model.current, model.result != nil {
                resultPane(current)
            } else {
                emptyState
            }
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(L("See what takes up space", "Xem cái gì đang chiếm chỗ"), systemImage: "chart.bar.xaxis")
        } description: {
            Text(L("Pinax scans a folder and shows the biggest items level by level. Everything you remove goes to the Trash and can be undone.",
                   "Pinax quét một thư mục và cho thấy mục nặng nhất theo từng cấp. Mọi thứ bạn xoá đều vào Thùng rác và hoàn tác được."))
        } actions: {
            Button(L("Scan Home", "Quét Home")) { model.scanHome() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func resultPane(_ current: SizeNode) -> some View {
        VStack(spacing: 0) {
            if model.isStale {
                HStack {
                    Image(systemName: "exclamationmark.circle")
                    Text(L("Results may be out of date", "Kết quả có thể đã cũ"))
                    Text("·")
                    Button(L("Rescan", "Quét lại")) { model.rescan() }.buttonStyle(.link)
                    Spacer()
                }
                .font(.callout).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(.quaternary.opacity(0.5))
            }
            ProportionBar(node: current)
                .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 8)
            childList(current)
            if model.unreadableCount > 0 { unreadableFooter }
            actionBar
        }
    }

    private func childList(_ current: SizeNode) -> some View {
        @Bindable var model = model
        let children = current.children
        let maxSize = max(children.first?.size ?? 1, 1)
        let colors = colorMap(children)
        return List(selection: $model.selection) {
            ForEach(children) { node in
                SpaceRowView(node: node, parentSize: current.size, maxSize: maxSize, color: colors[ObjectIdentifier(node)])
                    .tag(ObjectIdentifier(node))
            }
        }
        .contextMenu(forSelectionType: ObjectIdentifier.self) { ids in
            rowMenu(nodes(ids, in: current))
        } primaryAction: { ids in
            if let n = nodes(ids, in: current).first { model.open(n) }
        }
        .onKeyPress(.space) {
            guard let n = model.selectedNodes.first, n.kind != .others else { return .ignored }
            quickLookURL = quickLookURL == nil ? n.url : nil
            return .handled
        }
        .onKeyPress(.return) {
            guard model.selectedNodes.count == 1, let n = model.selectedNodes.first, n.kind == .directory else { return .ignored }
            model.open(n)
            return .handled
        }
        .quickLookPreview($quickLookURL)
        .overlay {
            if children.isEmpty {
                Text(L("Nothing big in this folder", "Không có gì lớn trong thư mục này"))
                    .foregroundStyle(.secondary).allowsHitTesting(false)
            }
        }
    }

    private func nodes(_ ids: Set<ObjectIdentifier>, in current: SizeNode) -> [SizeNode] {
        current.children.filter { ids.contains(ObjectIdentifier($0)) }
    }

    private func colorMap(_ children: [SizeNode]) -> [ObjectIdentifier: Color] {
        var out: [ObjectIdentifier: Color] = [:]
        for (i, n) in children.filter({ $0.kind != .others }).prefix(spacePalette.count).enumerated() {
            out[ObjectIdentifier(n)] = spacePalette[i]
        }
        return out
    }

    @ViewBuilder private func rowMenu(_ nodes: [SizeNode]) -> some View {
        if let first = nodes.first, nodes.count == 1, first.kind != .others {
            Button(L("Reveal in Browser", "Hiện trong trình duyệt")) { reveal(first) }
            Button(L("Quick Look", "Xem nhanh")) { quickLookURL = first.url }
            Button(L("Analyze Here", "Phân tích tại đây")) { model.scan(first.url) }
                .disabled(first.kind != .directory || first.skipped)
        }
        if !nodes.isEmpty {
            Divider()
            Button(L("Move to Trash", "Chuyển vào Thùng rác")) {
                // Menu chuột phải trên mục chưa chọn: chọn nó trước.
                model.selection = Set(nodes.map(ObjectIdentifier.init))
                model.trashSelection()
            }
            .disabled(!nodes.allSatisfy(model.canTrash))
        }
    }

    private func reveal(_ node: SizeNode) {
        browser.navigate(to: node.url.deletingLastPathComponent(), select: node.url.path)
    }

    // MARK: Chân

    private var unreadableFooter: some View {
        HStack {
            Image(systemName: "lock")
            Text(L("\(model.unreadableCount) folders couldn't be read", "\(model.unreadableCount) thư mục không đọc được"))
            Button(L("Open Full Disk Access", "Mở Toàn quyền truy cập ổ đĩa")) {
                NSWorkspace.shared.open(FullDiskAccess.settingsURL)
            }
            .buttonStyle(.link)
            Spacer()
        }
        .font(.callout).foregroundStyle(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 6)
        .overlay(alignment: .top) { Divider() }
    }

    private var actionBar: some View {
        let nodes = model.selectedNodes
        let bytes = nodes.reduce(Int64(0)) { $0 + $1.size }
        return HStack {
            Text(nodes.isEmpty
                 ? L("Nothing selected", "Chưa chọn gì")
                 : L("\(itemsText(nodes.count)) selected · \(fmtBytes(bytes))", "Đã chọn \(itemsText(nodes.count)) · \(fmtBytes(bytes))"))
                .foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
            Button(L("Reveal in Browser", "Hiện trong trình duyệt")) {
                if let n = nodes.first { reveal(n) }
            }
            .disabled(nodes.count != 1 || nodes[0].kind == .others)
            Button(L("Move to Trash", "Chuyển vào Thùng rác")) { model.trashSelection() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canTrashSelection)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

// MARK: - Đang quét

private struct ScanningPane: View {
    @Environment(SpaceMapModel.self) private var model
    let progress: SpaceScanner.Progress?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text(L("Scanning… \(fmtCount(progress?.files ?? 0)) files · \(fmtBytes(progress?.bytes ?? 0))",
                       "Đang quét… \(fmtCount(progress?.files ?? 0)) file · \(fmtBytes(progress?.bytes ?? 0))"))
                    .monospacedDigit()
                Spacer()
                Button(L("Cancel", "Huỷ")) { model.cancel() }
            }
            Text(progress?.currentPath ?? "")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle)
            let done = (progress?.finishedTopLevel ?? []).sorted { $0.size > $1.size }
            List(Array(done.enumerated()), id: \.offset) { _, e in
                HStack(spacing: 10) {
                    Image(systemName: e.isDirectory ? "folder" : "doc").foregroundStyle(.secondary)
                    Text(e.name).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(fmtBytes(e.size)).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .listStyle(.bordered)
        }
        .padding(16)
    }
}

// MARK: - Thanh tỉ lệ

private struct ProportionBar: View {
    let node: SizeNode

    var body: some View {
        let total = max(node.size, 1)
        let top = node.children.filter { $0.kind != .others }.prefix(spacePalette.count)
        let topSum = top.reduce(Int64(0)) { $0 + $1.size }
        let rest = max(node.size - topSum, 0)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(Array(top.enumerated()), id: \.offset) { i, n in
                        spacePalette[i].frame(width: width(n.size, total, geo.size.width))
                    }
                    if rest > 0 {
                        Color.gray.opacity(0.5).frame(width: width(rest, total, geo.size.width))
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 14)
            HStack(spacing: 12) {
                Text(fmtBytes(node.size)).font(.caption.weight(.semibold)).monospacedDigit()
                ForEach(Array(top.prefix(4).enumerated()), id: \.offset) { i, n in
                    HStack(spacing: 4) {
                        Circle().fill(spacePalette[i]).frame(width: 7, height: 7)
                        Text(nodeName(n)).lineLimit(1)
                    }
                }
                if top.count > 4 || rest > 0 {
                    HStack(spacing: 4) {
                        Circle().fill(Color.gray.opacity(0.5)).frame(width: 7, height: 7)
                        Text(L("Other", "Khác"))
                    }
                }
                Spacer()
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func width(_ size: Int64, _ total: Int64, _ full: CGFloat) -> CGFloat {
        max(CGFloat(Double(size) / Double(total)) * full, size > 0 ? 2 : 0)
    }
}

// MARK: - Dòng

private struct SpaceRowView: View {
    @Environment(SpaceMapModel.self) private var model
    let node: SizeNode
    let parentSize: Int64
    let maxSize: Int64
    let color: Color?

    var body: some View {
        HStack(spacing: 10) {
            icon.frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(nodeName(node)).lineLimit(1).truncationMode(.middle)
                if let note { Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer(minLength: 8)
            if node.skipped {
                if model.scanningSkipped.contains(ObjectIdentifier(node)) {
                    ProgressView().controlSize(.small)
                } else {
                    Button(L("Scan", "Quét")) { model.scanSkipped(node) }.controlSize(.small)
                }
            }
            bar
            Text(fmtBytes(node.size)).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 76, alignment: .trailing)
            Text(percent).monospacedDigit().foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
            Text(node.kind == .others ? "" : fmtCount(node.fileCount)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1)
                .frame(width: 84, alignment: .trailing)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var icon: some View {
        if node.kind == .others {
            Image(systemName: "ellipsis.circle").foregroundStyle(.secondary)
        } else {
            Image(nsImage: IconCache.shared.icon(forPath: node.url.path, size: 20))
        }
    }

    private var note: String? {
        if node.skipped { return L("Not scanned · macOS asks permission", "Chưa quét · macOS sẽ hỏi quyền") }
        if node.isUnreadable { return L("Can't read", "Không đọc được") }
        return nil
    }

    private var bar: some View {
        let frac = CGFloat(Double(node.size) / Double(max(maxSize, 1)))
        return Capsule().fill(.quaternary).frame(width: 120, height: 8)
            .overlay(alignment: .leading) {
                Capsule().fill(color ?? Color.gray.opacity(0.6)).frame(width: max(120 * frac, node.size > 0 ? 3 : 0), height: 8)
            }
    }

    private var percent: String {
        guard parentSize > 0 else { return "" }
        let p = Double(node.size) / Double(parentSize) * 100
        return p < 0.1 ? "<0.1%" : String(format: "%.1f%%", p)
    }
}

/// Số có phân cách hàng nghìn theo locale.
private func fmtCount(_ n: Int) -> String { n.formatted(.number) }
