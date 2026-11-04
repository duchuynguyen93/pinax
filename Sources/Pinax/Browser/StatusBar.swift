import SwiftUI

struct StatusBar: View {
    let model: BrowserModel

    var body: some View {
        HStack {
            Text(summary)
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background(.bar)
    }

    private var summary: String {
        var s = itemsText(model.items.count) + ", " + selectedText(model.selection.count)
        if let free = model.availableBytes { s += " · " + availableText(fmtBytes(free)) }
        return s
    }
}
