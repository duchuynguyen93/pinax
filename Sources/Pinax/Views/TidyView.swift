import SwiftUI
import PinaxCore

struct TidyView: View {
    @Environment(TidyModel.self) private var model
    @State private var expandedKinds: Set<FileKind> = []

    var body: some View {
        VStack(spacing: 0) {
            header.padding(20)
            Divider()
            content
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        .onAppear { model.refresh() }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(abbreviate(model.folder)).font(.callout).foregroundStyle(.secondary)
                Text(L("Loose files are sorted into folders by type. Folders you already have are never touched.",
                       "File lẻ được xếp vào thư mục theo loại. Thư mục có sẵn không bị động tới."))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
            Button { model.refresh() } label: { Label(L("Refresh", "Làm mới"), systemImage: "arrow.clockwise") }
                .disabled(model.isLoading || model.isPerforming)
        }
    }

    @ViewBuilder private var content: some View {
        if let plan = model.plan {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if plan.tidyMoves.isEmpty {
                        ContentUnavailableView(L("Nothing to tidy", "Không có gì cần sắp xếp"),
                                               systemImage: "checkmark.circle",
                                               description: Text(L("There are no loose files that can be sorted right now.",
                                                                   "Hiện không có file lẻ nào để sắp xếp.")))
                            .frame(maxWidth: .infinity)
                    } else {
                        summary(plan)
                        VStack(spacing: 8) {
                            ForEach(FileKind.allCases.filter { k in plan.tidyMoves.contains { $0.kind == k } }, id: \.self) { kind in
                                kindCard(kind, plan)
                            }
                        }
                    }
                    if !plan.skipped.isEmpty { skippedSection(plan) }
                }
                .padding(20)
            }
        } else {
            VStack { ProgressView() }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func summary(_ plan: TidyPlan) -> some View {
        let total = plan.bytesByKind.values.reduce(0, +)
        return VStack(alignment: .leading, spacing: 8) {
            Text(L("\(itemsText(plan.tidyMoves.count)) · \(fmtBytes(total)) by type", "\(itemsText(plan.tidyMoves.count)) · \(fmtBytes(total)) theo loại"))
                .font(.headline).monospacedDigit()
            GeometryReader { geo in
                HStack(spacing: 1) {
                    ForEach(FileKind.allCases.filter { (plan.bytesByKind[$0] ?? 0) > 0 }, id: \.self) { k in
                        Rectangle().fill(color(k))
                            .frame(width: max(2, geo.size.width * CGFloat(plan.bytesByKind[k] ?? 0) / CGFloat(max(total, 1))))
                            .opacity(model.disabledKinds.contains(k) ? 0.25 : 1)
                    }
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .frame(height: 10)
        }
    }

    private func color(_ k: FileKind) -> Color {
        switch k {
        case .installers: .indigo
        case .archives: .brown
        case .images: .green
        case .videos: .purple
        case .audio: .pink
        case .documents: .blue
        case .code: .teal
        case .other: .gray
        }
    }

    private func kindCard(_ kind: FileKind, _ plan: TidyPlan) -> some View {
        let moves = plan.tidyMoves.filter { $0.kind == kind }
        let on = !model.disabledKinds.contains(kind)
        let open = expandedKinds.contains(kind)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Toggle("", isOn: Binding(get: { on }, set: { _ in model.toggleKind(kind) }))
                    .labelsHidden().toggleStyle(.checkbox)
                Image(systemName: kindSymbol(kind)).foregroundStyle(color(kind)).frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kindName(kind)).font(.headline)
                    Text(L("into \(kind.folderName)/", "vào \(kind.folderName)/")).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(fmtBytes(plan.bytesByKind[kind] ?? 0)).font(.headline).monospacedDigit()
                    Text(itemsText(moves.count)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Image(systemName: "chevron.right").rotationEffect(.degrees(open ? 90 : 0)).foregroundStyle(.secondary)
            }
            .padding(12)
            .contentShape(Rectangle())
            .onTapGesture {
                if open { expandedKinds.remove(kind) } else { expandedKinds.insert(kind) }
            }
            if open {
                Divider().padding(.horizontal, 12)
                ForEach(moves.prefix(100), id: \.from) { m in
                    HStack {
                        Text(m.from.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        if m.to.lastPathComponent != m.from.lastPathComponent {
                            Text("→ \(m.to.lastPathComponent)").font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(fmtBytes(m.size)).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .padding(.horizontal, 44).padding(.vertical, 5)
                }
                if moves.count > 100 {
                    Text(L("and \(moves.count - 100) more", "và \(moves.count - 100) mục nữa"))
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 44).padding(.bottom, 8)
                }
            }
        }
        .opacity(on ? 1 : 0.55)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
    }

    private func skippedSection(_ plan: TidyPlan) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(plan.skipped.prefix(200).enumerated()), id: \.offset) { _, item in
                    HStack {
                        Text(item.0.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(tidySkipText(item.1)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text(L("Skipped (\(plan.skipped.count))", "Đã bỏ qua (\(plan.skipped.count))")).font(.headline)
        }
    }

    private var bottomBar: some View {
        HStack {
            if let f = model.filtered, !f.tidyMoves.isEmpty {
                Text(L("\(itemsText(f.tidyMoves.count)) will be sorted", "Sẽ sắp xếp \(itemsText(f.tidyMoves.count))"))
                    .foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
            if model.isPerforming { ProgressView().controlSize(.small) }
            Button(L("Tidy", "Sắp xếp")) { model.tidy() }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canTidy)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
