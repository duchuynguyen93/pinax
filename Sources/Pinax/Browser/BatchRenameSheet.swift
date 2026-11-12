import SwiftUI
import PinaxCore

/// Sheet đổi tên hàng loạt: chọn kiểu, xem trước tên mới từng dòng, Rename chạy qua `BrowserModel.applyBatchRename`.
struct BatchRenameSheet: View {
    enum Mode: Hashable { case replace, add, format, changeCase }

    let urls: [URL]
    let onApply: ([RenameEntry]) -> Void
    let onCancel: () -> Void

    @State private var mode: Mode
    @State private var find = ""
    @State private var replacement = ""
    @State private var matchCase = false
    @State private var includeExtension = false
    @State private var addText = ""
    @State private var addAtEnd = true
    @State private var base: String
    @State private var numberFirst = false
    @State private var start = 1
    @State private var digits = 0
    @State private var separator = " "
    @State private var caseStyle = RenameRule.CaseStyle.title
    @State private var entries: [RenameEntry] = []
    @State private var computing = false

    /// `qaPreset` (QA): format | replace | add | case → mở sẵn kiểu đó với giá trị mẫu.
    init(urls: [URL], qaPreset: String? = nil,
         onApply: @escaping ([RenameEntry]) -> Void, onCancel: @escaping () -> Void) {
        self.urls = urls
        self.onApply = onApply
        self.onCancel = onCancel
        _mode = State(initialValue: .replace)
        _base = State(initialValue: urls.first?.deletingPathExtension().lastPathComponent ?? "")
        switch qaPreset {
        case "format": _mode = State(initialValue: .format); _base = State(initialValue: "Ảnh Đà Lạt"); _digits = State(initialValue: 3)
        case "replace": _mode = State(initialValue: .replace); _find = State(initialValue: "IMG_"); _replacement = State(initialValue: "Ảnh ")
        case "add": _mode = State(initialValue: .add); _addText = State(initialValue: " (bản cũ)")
        case "case": _mode = State(initialValue: .changeCase); _caseStyle = State(initialValue: .title)
        default: break
        }
    }

    private var rule: RenameRule {
        switch mode {
        case .replace: .replace(find: find, with: replacement, caseSensitive: matchCase, includeExtension: includeExtension)
        case .add: .add(text: addText, atEnd: addAtEnd)
        case .format: .format(base: base, start: start, digits: digits, numberFirst: numberFirst, separator: separator)
        case .changeCase: .changeCase(caseStyle, includeExtension: includeExtension)
        }
    }

    private var renameCount: Int { entries.filter { $0.issue == nil }.count }
    private var problemCount: Int { entries.filter { if let i = $0.issue { i != .unchanged } else { false } }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L("Rename \(urls.count) items", "Đổi tên \(urls.count) mục"))
                .font(.title3.weight(.semibold))
            Picker("", selection: $mode) {
                Text(L("Replace Text", "Thay chữ")).tag(Mode.replace)
                Text(L("Add Text", "Thêm chữ")).tag(Mode.add)
                Text(L("Format", "Định dạng")).tag(Mode.format)
                Text(L("Change Case", "Hoa thường")).tag(Mode.changeCase)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            fields
            List(entries, id: \.source) { e in row(e) }
                .listStyle(.bordered)
                .frame(minHeight: 160, maxHeight: .infinity)
            HStack {
                Text(L("\(renameCount) will be renamed · \(problemCount) problems",
                       "\(renameCount) mục sẽ đổi tên · \(problemCount) lỗi"))
                    .font(.callout)
                    .foregroundStyle(problemCount > 0 ? Color.red : Color.secondary)
                Spacer()
                Button(L("Cancel", "Huỷ"), action: onCancel).keyboardShortcut(.cancelAction)
                Button(L("Rename", "Đổi tên")) { onApply(entries) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(computing || !BatchRename.canApply(entries))
            }
        }
        .padding(22)
        .frame(minWidth: 620, idealWidth: 620, minHeight: 520, idealHeight: 520)
        .task(id: rule) { await recompute() }
    }

    // MARK: Ô nhập theo kiểu

    @ViewBuilder private var fields: some View {
        switch mode {
        case .replace:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField(L("Find", "Tìm"), text: $find)
                    TextField(L("Replace with", "Thay bằng"), text: $replacement)
                }
                HStack(spacing: 18) {
                    Toggle(L("Match case", "Phân biệt hoa thường"), isOn: $matchCase)
                    Toggle(L("Include extension", "Gồm cả đuôi file"), isOn: $includeExtension)
                }
            }
        case .add:
            HStack {
                TextField(L("Text", "Chữ cần thêm"), text: $addText)
                Picker("", selection: $addAtEnd) {
                    Text(L("Before name", "Trước tên")).tag(false)
                    Text(L("After name", "Sau tên")).tag(true)
                }
                .labelsHidden()
                .fixedSize()
            }
        case .format:
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField(L("Name", "Tên"), text: $base)
                    Picker("", selection: $numberFirst) {
                        Text(L("Number after name", "Số sau tên")).tag(false)
                        Text(L("Number before name", "Số trước tên")).tag(true)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                HStack(spacing: 18) {
                    Stepper(L("Start at \(start)", "Bắt đầu từ \(start)"), value: $start, in: 0...999_999)
                    Stepper(L("Digits: \(digits)", "Số chữ số: \(digits)"), value: $digits, in: 0...6)
                    // Mặc định là một dấu cách (nhìn như ô trống) → có nhãn bên cạnh.
                    LabeledContent(L("Separator:", "Ngăn cách:")) {
                        TextField(L("Separator", "Ngăn cách"), text: $separator).frame(width: 60)
                    }
                }
            }
        case .changeCase:
            HStack(spacing: 18) {
                Picker("", selection: $caseStyle) {
                    Text("lowercase").tag(RenameRule.CaseStyle.lower)
                    Text("UPPERCASE").tag(RenameRule.CaseStyle.upper)
                    Text("Title Case").tag(RenameRule.CaseStyle.title)
                }
                .labelsHidden()
                .fixedSize()
                Toggle(L("Include extension", "Gồm cả đuôi file"), isOn: $includeExtension)
            }
        }
    }

    // MARK: Xem trước

    private func row(_ e: RenameEntry) -> some View {
        let bad = e.issue.map { $0 != .unchanged } ?? false
        let same = e.issue == .unchanged
        return HStack(spacing: 8) {
            Text(e.source.lastPathComponent).lineLimit(1).truncationMode(.middle)
            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
            Text(e.newName).lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            if let reason = reasonText(e.issue) {
                Text(reason).font(.caption).foregroundStyle(.red)
            }
        }
        .foregroundStyle(bad ? Color.red : same ? Color.secondary : Color.primary)
    }

    private func reasonText(_ issue: RenameEntry.Issue?) -> String? {
        switch issue {
        case .invalid: L("Invalid name", "Tên không hợp lệ")
        case .duplicateInBatch: L("Duplicate name", "Trùng tên")
        case .exists: L("Already exists", "Đã tồn tại")
        case .unchanged, nil: nil
        }
    }

    /// Tính lại preview. > 500 mục thì ngoài main; `.task(id:)` huỷ lượt cũ khi rule đổi nên kết quả cũ không đè kết quả mới.
    private func recompute() async {
        let urls = urls, rule = rule
        if urls.count <= 500 {
            entries = BatchRename.plan(urls, rule: rule)
            computing = false
            return
        }
        computing = true
        let result = await Task.detached(priority: .userInitiated) { BatchRename.plan(urls, rule: rule) }.value
        guard !Task.isCancelled else { return }
        entries = result
        computing = false
    }
}
