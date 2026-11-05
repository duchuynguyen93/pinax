import SwiftUI
import PinaxCore

/// Dải tiến độ chép / chuyển ngay trên status bar; ẩn khi hàng đợi rỗng.
struct TransferStrip: View {
    @Environment(TransferQueue.self) private var queue

    var body: some View {
        if let job = queue.current {
            VStack(spacing: 0) {
                Divider()
                row(job)
            }
        }
    }

    private func row(_ job: TransferJob) -> some View {
        let p = job.progress
        return HStack(spacing: 8) {
            Text(job.title).lineLimit(1).truncationMode(.middle).frame(maxWidth: 260, alignment: .leading)
            bar(p.map(fraction) ?? 0)
            Text(detail(p, total: job.totalItems)).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if !queue.queued.isEmpty {
                Text(L("+\(queue.queued.count) queued", "+\(queue.queued.count) đang chờ"))
            }
            Button { job.cancel() } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.plain)
                .help(L("Stop", "Dừng"))
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.bar)
    }

    /// Thanh tự vẽ: ProgressView tuyến tính trên macOS 27 vẽ dải gradient khó đọc phần trăm.
    private func bar(_ f: Double) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(.quaternary)
            Capsule().fill(Color.accentColor).frame(width: max(6, 140 * f))
        }
        .frame(width: 140, height: 6)
        .animation(.linear(duration: 0.1), value: f)
        .accessibilityElement()
        .accessibilityValue(Text("\(Int(f * 100))%"))
    }

    private func fraction(_ p: TransferProgress) -> Double {
        let f = p.totalBytes > 0 ? Double(p.completedBytes) / Double(p.totalBytes)
                                 : Double(p.completedItems) / Double(max(p.totalItems, 1))
        return min(max(f, 0), 1)
    }

    /// Có số byte thì hiện "1,2 GB of 3,4 GB", không thì số mục; kèm tên đang chép.
    private func detail(_ p: TransferProgress?, total: Int) -> String {
        var s: String
        if let p, p.totalBytes > 0 {
            let f = ByteCountFormatter()
            f.countStyle = .file
            s = L("\(f.string(fromByteCount: p.completedBytes)) of \(f.string(fromByteCount: p.totalBytes))",
                  "\(f.string(fromByteCount: p.completedBytes)) / \(f.string(fromByteCount: p.totalBytes))")
        } else {
            let done = p?.completedItems ?? 0
            s = total == 1 ? L("\(done) of 1 item", "\(done)/1 mục") : L("\(done) of \(total) items", "\(done)/\(total) mục")
        }
        if let name = p?.currentName, !name.isEmpty { s += " · " + name }
        return s
    }
}
