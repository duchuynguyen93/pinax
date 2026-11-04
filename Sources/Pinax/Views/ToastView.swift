import SwiftUI

struct ToastView: View {
    @Environment(ToastModel.self) private var toast
    @State private var showProblems = false

    var body: some View {
        if let t = toast.current {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Image(systemName: t.problems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(t.problems.isEmpty ? Color.green : Color.orange)
                    Text(t.message).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if !t.problems.isEmpty {
                        Button(showProblems ? L("Hide details", "Ẩn chi tiết") : L("Details", "Chi tiết")) {
                            showProblems.toggle()
                        }
                        .buttonStyle(.link)
                    }
                    if t.undoBatch != nil {
                        Button(L("Undo", "Hoàn tác")) { toast.undoCurrent() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button { toast.dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(L("Dismiss", "Đóng"))
                }
                if showProblems && !t.problems.isEmpty {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(t.problems) { p in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(p.name).font(.callout).lineLimit(1).truncationMode(.middle)
                                    Text(p.detail).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 160)
                }
            }
            .padding(14)
            .frame(maxWidth: 620)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            .padding(.horizontal, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .onChange(of: t.id) { showProblems = false }
        }
    }
}
