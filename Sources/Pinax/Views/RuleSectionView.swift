import SwiftUI
import PinaxCore

struct RuleSectionView: View {
    let title: String
    let subtitle: String
    let rules: [any CleanRule]

    var body: some View {
        if !rules.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                }
                VStack(spacing: 8) {
                    ForEach(rules, id: \.id) { rule in
                        RuleRowView(ruleID: rule.id)
                    }
                }
            }
        }
    }
}

struct TriStateCheckbox: View {
    let state: SmartCleanModel.CheckState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: state == .on ? "checkmark.square.fill" : state == .mixed ? "minus.square.fill" : "square")
                .font(.title3)
                .foregroundStyle(state == .off ? Color.secondary : Color.accentColor)
        }
        .buttonStyle(.borderless)
        .accessibilityValue(state == .on ? L("selected", "đã chọn") : state == .mixed ? L("partly selected", "chọn một phần") : L("not selected", "chưa chọn"))
    }
}

struct RuleRowView: View {
    @Environment(SmartCleanModel.self) private var model
    let ruleID: String

    private var result: RuleResult? { model.results[ruleID] }
    private var items: [Candidate] { result?.candidates ?? [] }
    private var isExpanded: Bool { model.expanded.contains(ruleID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded && !items.isEmpty {
                Divider().padding(.horizontal, 12)
                itemList
            }
        }
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
    }

    @ViewBuilder private var header: some View {
        HStack(spacing: 12) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(ruleTitle(ruleID)).font(.headline)
                Text(ruleBlurb(ruleID)).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                statusLine
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(12)
        .contentShape(Rectangle())
        .onTapGesture { if !items.isEmpty { model.toggleExpanded(ruleID) } }
    }

    @ViewBuilder private var leading: some View {
        switch result?.status {
        case .none:
            switch model.progress[ruleID] {
            case .done: Image(systemName: "checkmark.circle").font(.title3).foregroundStyle(.secondary)
            default: ProgressView().controlSize(.small).frame(width: 20)
            }
        case .some(.needsFullDiskAccess):
            Image(systemName: "lock.trianglebadge.exclamationmark.fill").font(.title3).foregroundStyle(.orange)
        case .some(.failed):
            Image(systemName: "exclamationmark.circle").font(.title3).foregroundStyle(.secondary)
        case .some(.ok):
            if items.isEmpty {
                Image(systemName: "checkmark.circle").font(.title3).foregroundStyle(.secondary)
            } else {
                TriStateCheckbox(state: model.checkState(for: ruleID)) { model.toggleRule(ruleID) }
            }
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch result?.status {
        case .none:
            if case .done(let count, let bytes) = model.progress[ruleID] {
                Text(L("\(itemsText(count)) · \(fmtBytes(bytes))", "\(itemsText(count)) · \(fmtBytes(bytes))"))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            } else {
                Text(L("Scanning…", "Đang quét…")).font(.caption).foregroundStyle(.secondary)
            }
        case .some(.needsFullDiskAccess):
            Text(L("Needs Full Disk Access to look here.", "Cần quyền Toàn bộ ổ đĩa (Full Disk Access) để xem mục này."))
                .font(.caption).foregroundStyle(.orange)
        case .some(.failed(let msg)):
            Text(L("Could not scan: \(msg)", "Không quét được: \(msg)")).font(.caption).foregroundStyle(.red)
        case .some(.ok):
            if items.isEmpty {
                Text(L("Nothing found", "Không có gì để dọn")).font(.caption).foregroundStyle(.secondary)
            } else if ruleID == "duplicates" {
                Text(L("APFS clones may free less space than shown.", "APFS clone có thể khiến dung lượng thu hồi thực tế ít hơn con số hiển thị."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var trailing: some View {
        switch result?.status {
        case .some(.needsFullDiskAccess):
            Button(L("Open System Settings", "Mở Cài đặt hệ thống")) {
                NSWorkspace.shared.open(FullDiskAccess.settingsURL)
            }
        case .some(.ok) where !items.isEmpty:
            HStack(spacing: 10) {
                VStack(alignment: .trailing, spacing: 1) {
                    Text(fmtBytes(items.reduce(0) { $0 + $1.size })).font(.headline).monospacedDigit()
                    Text(itemsText(items.count)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .foregroundStyle(.secondary)
                    .animation(.snappy(duration: 0.15), value: isExpanded)
            }
        default:
            EmptyView()
        }
    }

    private var itemList: some View {
        VStack(spacing: 0) {
            ForEach(items.prefix(SmartCleanModel.visibleItemLimit)) { c in
                CandidateRow(candidate: c)
                if c.id != items.prefix(SmartCleanModel.visibleItemLimit).last?.id { Divider().padding(.leading, 44) }
            }
            if items.count > SmartCleanModel.visibleItemLimit {
                Text(L("Showing the largest \(SmartCleanModel.visibleItemLimit) of \(items.count). The checkbox above still covers all of them.",
                       "Hiển thị \(SmartCleanModel.visibleItemLimit) mục lớn nhất trong \(items.count). Ô chọn phía trên vẫn áp dụng cho tất cả."))
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(10)
            }
        }
    }
}

struct CandidateRow: View {
    @Environment(SmartCleanModel.self) private var model
    let candidate: Candidate

    var body: some View {
        let on = model.selected.contains(candidate.id)
        HStack(spacing: 12) {
            Button { model.toggle(candidate) } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .padding(.leading, 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(abbreviate(candidate.url.deletingLastPathComponent()))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                Text(reasonText(candidate)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Text(fmtBytes(candidate.size)).monospacedDigit().foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
            } label: { Image(systemName: "magnifyingglass.circle") }
            .buttonStyle(.borderless)
            .help(L("Show in Finder", "Hiện trong Finder"))
            .padding(.trailing, 12)
        }
        .padding(.vertical, 7)
        .background(model.focusedID == candidate.id ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.focusedID = candidate.id }
    }
}
