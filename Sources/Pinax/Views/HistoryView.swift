import SwiftUI
import PinaxCore

struct HistoryView: View {
    @Environment(HistoryModel.self) private var history
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        Group {
            if history.batches.isEmpty {
                ContentUnavailableView(L("No history yet", "Chưa có lịch sử"), systemImage: "clock",
                                       description: Text(L("Everything Pinax moves shows up here, and can be undone.",
                                                           "Mọi thứ Pinax di chuyển sẽ hiện ở đây và hoàn tác được.")))
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(history.batches) { batch in BatchCard(batch: batch) }
                    }
                    .padding(20)
                }
            }
        }
        .onAppear { history.reload() }
    }
}

private struct BatchCard: View {
    @Environment(HistoryModel.self) private var history
    @Environment(AppEnvironment.self) private var env
    let batch: Batch

    var body: some View {
        let outcomes = history.undoOutcomes[batch.id]
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(batch.title).font(.headline)
                    Text("\(batch.date.formatted(date: .abbreviated, time: .shortened)) · \(L("\(batch.ops.count) steps", "\(batch.ops.count) bước"))")
                        .font(.callout).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
                if batch.undone {
                    Label(L("Undone", "Đã hoàn tác"), systemImage: "arrow.uturn.backward.circle")
                        .foregroundStyle(.secondary)
                }
                Button(L("Undo", "Hoàn tác")) { env.undo(batch) }
                    .disabled(batch.undone || history.isUndoing)
            }
            if let outcomes {
                Divider()
                let done = outcomes.filter { $0.status == .done }.count
                Text(L("Restored \(done) of \(outcomes.count)", "Đã khôi phục \(done)/\(outcomes.count)"))
                    .font(.callout)
                ForEach(Array(outcomes.prefix(100).enumerated()), id: \.offset) { _, o in
                    HStack(spacing: 6) {
                        Image(systemName: icon(o.status)).foregroundStyle(color(o.status))
                        Text(abbreviate(o.url)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        if let p = Problem.from(o) { Text(p.detail).font(.caption).foregroundStyle(.secondary) }
                    }
                    .font(.callout)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
        .opacity(batch.undone && outcomes == nil ? 0.7 : 1)
    }

    private func icon(_ s: ItemStatus) -> String {
        switch s {
        case .done: "checkmark.circle.fill"
        case .skipped: "minus.circle"
        case .failed: "xmark.circle.fill"
        }
    }

    private func color(_ s: ItemStatus) -> Color {
        switch s {
        case .done: .green
        case .skipped: .orange
        case .failed: .red
        }
    }
}
