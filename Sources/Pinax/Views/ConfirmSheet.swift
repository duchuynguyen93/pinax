import SwiftUI
import PinaxCore

struct ConfirmSheet: View {
    let items: [Candidate]
    let bytes: Int64
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Move \(itemsText(items.count)) to the Trash?", "Chuyển \(itemsText(items.count)) vào Thùng rác?"))
                .font(.title3.weight(.semibold))
            Text(L("\(fmtBytes(bytes)) will be moved to the Trash. Nothing is deleted permanently, and you can undo this right after (or from History).",
                   "\(fmtBytes(bytes)) sẽ được chuyển vào Thùng rác. Không có gì bị xoá vĩnh viễn, và bạn hoàn tác được ngay sau đó (hoặc trong Lịch sử)."))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            List(items.prefix(8)) { c in
                HStack {
                    Text(c.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Text(fmtBytes(c.size)).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            .listStyle(.bordered)
            .frame(height: 190)
            if items.count > 8 {
                Text(L("and \(items.count - 8) more", "và \(items.count - 8) mục nữa"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button(L("Cancel", "Huỷ"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Move to Trash", "Chuyển vào Thùng rác"), action: onConfirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 480)
    }
}
