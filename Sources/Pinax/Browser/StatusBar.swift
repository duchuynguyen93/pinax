import SwiftUI

struct StatusBar: View {
    let model: BrowserModel
    /// Pane không active trong dual → chữ mờ đi.
    var dimmed = false

    var body: some View {
        HStack {
            Text(summary)
            Spacer()
        }
        .opacity(dimmed ? 0.5 : 1)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(.bar)
    }

    private var summary: String {
        if model.isSearching { return searchSummary }
        var s = itemsText(model.items.count) + ", " + selectedText(model.selection.count)
        if let free = model.availableBytes { s += " · " + availableText(fmtBytes(free)) }
        return s
    }

    /// "N results for “q”" (+ đang tìm / bị cắt), kèm số mục chọn.
    private var searchSummary: String {
        let n = model.items.count, q = model.searchText.trimmingCharacters(in: .whitespaces)
        let count = n.formatted()
        var s = n == 1 ? L("1 result for “\(q)”", "1 kết quả cho “\(q)”") : L("\(count) results for “\(q)”", "\(count) kết quả cho “\(q)”")
        if model.searchRunning { s += L(" · searching…", " · đang tìm…") }
        if model.searchTruncated { s += L(" · showing first \(BrowserModel.searchLimit.formatted())", " · chỉ hiện \(BrowserModel.searchLimit.formatted()) kết quả đầu") }
        return s + ", " + selectedText(model.selection.count)
    }
}
