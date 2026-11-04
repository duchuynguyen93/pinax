import SwiftUI
import AppKit

/// Breadcrumb bấm được; ⌘L đổi thành ô gõ đường dẫn.
struct PathBar: View {
    let model: BrowserModel
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
                // Chỗ cho git ở path bar (bước D).
                trailingSlot
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        // Bấm vào vùng trống của path bar = gõ đường dẫn (nút breadcrumb tự nhận click của chúng).
        .contentShape(Rectangle())
        .onTapGesture { if !model.pathEditing { model.pathEditing = true } }
        .overlay(alignment: .topLeading) { suggestionList.offset(y: 30) }
        .zIndex(1)
    }

    @ViewBuilder private var trailingSlot: some View { EmptyView() }

    private static func editText(_ url: URL) -> String {
        let p = (url.path as NSString).abbreviatingWithTildeInPath
        return p.hasSuffix("/") ? p : p + "/"
    }

    private var crumbs: some View {
        let list = Self.components(of: model.folder)
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, url in
                    if i > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    Button { model.navigate(to: url) } label: {
                        HStack(spacing: 4) {
                            Image(nsImage: IconCache.shared.icon(forPath: url.path, size: 14))
                            Text(FileManager.default.displayName(atPath: url.path)).lineLimit(1)
                        }
                        .padding(.horizontal, 4).padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .defaultScrollAnchor(.trailing)
        .id(model.folder.path)
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
