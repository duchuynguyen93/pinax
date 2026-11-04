import SwiftUI
import PinaxCore

struct SmartCleanView: View {
    @Environment(SmartCleanModel.self) private var model
    @State private var showConfirm = false

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                StorageBarView(info: model.storage, selectedBytes: model.effectiveBytes)
                HStack {
                    scanButton
                    if model.phase == .scanning {
                        ProgressView().controlSize(.small)
                        Text(L("Scanning…", "Đang quét…")).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                if model.phase == .scanning {
                    Text(L("macOS may ask Pinax for access to Desktop, Documents or Downloads — the scan waits until you answer.",
                           "macOS có thể hỏi quyền truy cập Desktop, Documents hoặc Downloads — quá trình quét sẽ chờ bạn trả lời."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(20)
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .sheet(isPresented: $showConfirm) {
            ConfirmSheet(items: model.effective, bytes: model.effectiveBytes) {
                showConfirm = false
                model.moveSelectedToTrash()
            } onCancel: {
                showConfirm = false
            }
        }
        .onAppear { model.refreshStorage() }
    }

    @ViewBuilder private var scanButton: some View {
        if model.phase == .scanning {
            Button(L("Cancel", "Huỷ")) { model.cancelScan() }
        } else {
            Button {
                model.startScan()
            } label: {
                Label(model.phase == .scanned ? L("Scan Again", "Quét lại") : L("Scan", "Quét"),
                      systemImage: "magnifyingglass")
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.isPerforming)
        }
    }

    @ViewBuilder private var content: some View {
        if model.phase == .idle {
            ContentUnavailableView {
                Label(L("Ready to scan", "Sẵn sàng quét"), systemImage: "sparkles")
            } description: {
                Text(L("Pinax looks for clutter and shows you what it found. Nothing moves until you confirm, and everything goes to the Trash so you can undo it.",
                       "Pinax tìm đồ thừa rồi cho bạn xem. Không có gì bị động tới cho đến khi bạn xác nhận; mọi thứ đều vào Thùng rác và hoàn tác được."))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    RuleSectionView(title: L("Safe to clear", "An toàn để dọn"),
                                    subtitle: L("Regenerable or already-used files.", "Có thể tạo lại hoặc đã dùng xong."),
                                    rules: model.rules.filter { $0.group == .safe })
                    RuleSectionView(title: L("Your call", "Tuỳ bạn quyết"),
                                    subtitle: L("Only you know if you still need these. Review before moving.",
                                                "Chỉ bạn biết mình còn cần chúng không. Xem kỹ trước khi chuyển."),
                                    rules: model.rules.filter { $0.group == .review })
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder private var bottomBar: some View {
        if model.phase == .scanned {
            VStack(alignment: .leading, spacing: 8) {
                if !model.conflicts.isEmpty { conflictWarning }
                HStack {
                    Text(model.effective.isEmpty
                         ? L("Nothing selected", "Chưa chọn gì")
                         : L("\(itemsText(model.effective.count)) selected · \(fmtBytes(model.effectiveBytes))",
                             "Đã chọn \(itemsText(model.effective.count)) · \(fmtBytes(model.effectiveBytes))"))
                        .foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    if model.isPerforming { ProgressView().controlSize(.small) }
                    Button {
                        showConfirm = true
                    } label: {
                        Text(L("Move \(model.effective.count) items (\(fmtBytes(model.effectiveBytes))) to Trash",
                               "Chuyển \(model.effective.count) mục (\(fmtBytes(model.effectiveBytes))) vào Thùng rác"))
                            .monospacedDigit()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canMove)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
            .background(.bar)
            .overlay(alignment: .top) { Divider() }
        }
    }

    private var conflictWarning: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(L("You've selected every copy of the same file. Pinax won't move them all.",
                    "Bạn đang chọn tất cả các bản của cùng một file. Pinax sẽ không chuyển hết."),
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange).font(.callout.weight(.medium))
            ForEach(model.conflicts.prefix(4)) { c in
                Text("\(abbreviate(c.url))  →  \(reasonText(c))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            if model.conflicts.count > 4 {
                Text(L("and \(model.conflicts.count - 4) more", "và \(model.conflicts.count - 4) mục nữa"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(L("Deselect these duplicates", "Bỏ chọn các bản trùng này")) { model.deselectConflicts() }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
