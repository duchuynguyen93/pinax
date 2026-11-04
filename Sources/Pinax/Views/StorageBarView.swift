import SwiftUI

struct StorageBarView: View {
    let info: StorageInfo
    let selectedBytes: Int64

    private struct Segment: Identifiable {
        let id: String
        let label: String
        let bytes: Int64
        let color: Color
    }

    private var segments: [Segment] {
        let total = max(info.total, 1)
        let free = min(max(info.available, 0), total)
        let used = total - free
        var remaining = used
        func take(_ v: Int64?) -> Int64 {
            let x = min(max(v ?? 0, 0), remaining)
            remaining -= x
            return x
        }
        let apps = take(info.apps)
        let trash = info.trashUnreadable ? 0 : take(info.trash)
        let sel = take(selectedBytes)
        let other = remaining
        return [
            Segment(id: "apps", label: L("Apps", "Ứng dụng"), bytes: apps, color: .blue),
            Segment(id: "trash", label: L("Trash", "Thùng rác"), bytes: trash, color: .purple),
            Segment(id: "sel", label: L("Selected", "Đã chọn"), bytes: sel, color: .orange),
            Segment(id: "other", label: L("Other", "Khác"), bytes: other, color: Color.gray.opacity(0.55)),
            Segment(id: "free", label: L("Free", "Còn trống"), bytes: free, color: Color.primary.opacity(0.08)),
        ]
    }

    private func legendValue(_ s: Segment) -> String {
        if s.id == "trash" && info.trashUnreadable { return "—" }
        if (s.id == "apps" && info.apps == nil) || (s.id == "trash" && info.trash == nil) { return "…" }
        return fmtBytes(s.bytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(L("Startup disk", "Ổ khởi động")).font(.headline)
                Spacer()
                Text(L("\(fmtBytes(info.available)) free of \(fmtBytes(info.total))",
                       "Trống \(fmtBytes(info.available)) / \(fmtBytes(info.total))"))
                    .font(.callout).foregroundStyle(.secondary).monospacedDigit()
            }
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(segments) { s in
                        let w = geo.size.width * CGFloat(s.bytes) / CGFloat(max(info.total, 1))
                        if w > 0.5 { Rectangle().fill(s.color).frame(width: w) }
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: geo.size.width, alignment: .leading)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
            }
            .frame(height: 16)
            HStack(spacing: 16) {
                ForEach(segments) { s in
                    HStack(spacing: 5) {
                        Circle().fill(s.color).frame(width: 8, height: 8)
                            .overlay(Circle().strokeBorder(.separator, lineWidth: s.id == "free" ? 1 : 0))
                        Text(s.label).foregroundStyle(.secondary)
                        Text(legendValue(s))
                            .monospacedDigit()
                    }
                    .help(s.id == "trash" && info.trashUnreadable
                          ? L("Pinax needs Full Disk Access to measure the Trash",
                              "Pinax cần quyền Truy cập toàn bộ ổ đĩa để đo Thùng rác")
                          : "")
                    .font(.caption)
                }
                Spacer()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
