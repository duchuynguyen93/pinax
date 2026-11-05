import SwiftUI
import AppKit
import PinaxCore

/// Breadcrumb bấm được; ⌘L đổi thành ô gõ đường dẫn.
struct PathBar: View {
    let model: BrowserModel
    /// Dual pane: vạch accent 2pt ở đáy khi pane active; pane kia mờ đi.
    var dual = false
    var isActive = true
    @State private var suggestions: [String] = []
    @State private var suggestionIndex: Int?

    var body: some View {
        HStack(spacing: 8) {
            if model.pathEditing {
                Image(nsImage: IconCache.shared.icon(forPath: model.folder.path))
                PathField(initialText: Self.editText(model.folder),
                          onSubmit: { model.go(toPath: $0) },
                          onCancel: { model.pathEditing = false; suggestions = [] },
                          onSuggestions: { suggestions = $0; suggestionIndex = $1 })
                    .id(model.folder.path + "#edit")
            } else {
                crumbs
                trailingSlot
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) {
            if dual, isActive { Rectangle().fill(Color.accentColor).frame(height: 2) }
        }
        .opacity(dual && !isActive ? 0.55 : 1)
        // Bấm vào vùng trống của path bar = gõ đường dẫn (nút breadcrumb tự nhận click của chúng).
        .contentShape(Rectangle())
        .onTapGesture { if !model.pathEditing { model.pathEditing = true } }
        .overlay(alignment: .topLeading) { suggestionList.offset(y: 30) }
        .zIndex(1)
    }

    /// Git: `⎇ nhánh ↑1 ↓2 · 3 thay đổi`; ẩn khi không phải repo.
    @ViewBuilder private var trailingSlot: some View {
        if let g = model.git.summary {
            HStack(spacing: 6) {
                Text("⎇ \(g.branch.isEmpty ? "—" : g.branch)").lineLimit(1).truncationMode(.middle)
                if let ab = g.aheadBehindLabel { Text(ab) }
                if g.totalChanges > 0 { Text("· " + gitChangesLabel(g.totalChanges)) }
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .fixedSize()
            .help(Self.gitTooltip(g))
        }
    }

    private static func gitTooltip(_ g: GitSummary) -> String {
        var lines = [g.detached ? L("Detached HEAD at \(g.branch)", "HEAD tách rời tại \(g.branch)") : L("Branch \(g.branch)", "Nhánh \(g.branch)")]
        if g.ahead > 0 || g.behind > 0 {
            lines.append(L("\(g.ahead) ahead, \(g.behind) behind upstream", "Đi trước \(g.ahead), sau \(g.behind) so với upstream"))
        }
        if g.changeBreakdown.isEmpty {
            lines.append(L("Working tree clean", "Không có thay đổi"))
        } else {
            lines += g.changeBreakdown.map { gitChangeText($0.kind, $0.count) }
        }
        return lines.joined(separator: "\n")
    }

    private static func editText(_ url: URL) -> String {
        let p = (url.path as NSString).abbreviatingWithTildeInPath
        return p.hasSuffix("/") ? p : p + "/"
    }

    /// Breadcrumb căn trái. Quá dài → thu gọn các thành phần ở giữa vào menu "…" (giữ gốc và các mục cuối).
    private var crumbs: some View {
        let list = Self.components(of: model.folder)
        let maxHidden = max(0, list.count - 2)
        return FirstFit {
            ForEach(0...maxHidden, id: \.self) { hidden in
                crumbRow(list, hidden: hidden)
            }
            // Vẫn không vừa → chỉ còn thư mục hiện tại, cắt đuôi.
            crumbRow(list, hidden: maxHidden, lastOnly: true)
        }
        .clipped()
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(model.folder.path)
    }

    /// `hidden` = số thành phần giữa bị gộp (bỏ ngay sau gốc).
    private func crumbRow(_ list: [URL], hidden: Int, lastOnly: Bool = false) -> some View {
        let shown: [Int]
        let collapsed: [URL]
        if lastOnly {
            shown = [list.count - 1]
            collapsed = []
        } else {
            let first = list.isEmpty ? [] : [0]
            let tail = Array((1 + hidden)..<max(list.count, 1 + hidden))
            shown = first + tail
            collapsed = hidden > 0 ? Array(list[1..<(1 + hidden)]) : []
        }
        return HStack(spacing: 2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { pos, i in
                if pos > 0 { chevron }
                if pos == 1, !collapsed.isEmpty, !lastOnly {
                    Menu {
                        ForEach(Array(collapsed.enumerated()), id: \.offset) { _, url in
                            Button(FileManager.default.displayName(atPath: url.path)) { model.navigate(to: url) }
                        }
                    } label: { Text("…") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    chevron
                }
                crumb(list[i], truncates: lastOnly)
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
    }

    private func crumb(_ url: URL, truncates: Bool) -> some View {
        Button { model.navigate(to: url) } label: {
            HStack(spacing: 4) {
                Image(nsImage: IconCache.shared.icon(forPath: url.path, size: 14))
                Text(FileManager.default.displayName(atPath: url.path)).lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 4).padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func components(of url: URL) -> [URL] {
        var result: [URL] = []
        var path = url.path
        while true {
            result.insert(URL(fileURLWithPath: path, isDirectory: true), at: 0)
            if path == "/" || path.isEmpty { break }
            path = (path as NSString).deletingLastPathComponent
        }
        return result
    }

    @ViewBuilder private var suggestionList: some View {
        if model.pathEditing, !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(suggestions.prefix(8).enumerated()), id: \.offset) { i, s in
                    Text(s).lineLimit(1).truncationMode(.head)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(i == suggestionIndex ? Color.accentColor.opacity(0.25) : .clear)
                }
                if suggestions.count > 8 {
                    Text("… +\(suggestions.count - 8)").font(.caption).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                }
            }
            .frame(width: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .padding(.leading, 28)
        }
    }
}

/// Hiện con đầu tiên có chiều rộng lý tưởng vừa với chỗ được cấp (không có thì con cuối); các con khác ẩn.
private struct FirstFit: Layout {
    private func pick(_ subviews: Subviews, width: CGFloat?) -> Int {
        guard let width, width.isFinite else { return 0 }
        for (i, v) in subviews.enumerated() where v.sizeThatFits(.unspecified).width <= width { return i }
        return subviews.count - 1
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let i = pick(subviews, width: proposal.width)
        let s = subviews[i].sizeThatFits(i == subviews.count - 1 ? proposal : .unspecified)
        return CGSize(width: min(s.width, proposal.width ?? s.width), height: s.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let chosen = pick(subviews, width: bounds.width)
        for (i, v) in subviews.enumerated() {
            if i == chosen {
                v.place(at: bounds.origin, anchor: .topLeading,
                        proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
            } else {
                v.place(at: CGPoint(x: -20000, y: -20000), anchor: .topLeading, proposal: .zero)
            }
        }
    }
}
