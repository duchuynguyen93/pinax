import SwiftUI
import AppKit
import QuickLook
import PinaxCore

struct UninstallView: View {
    @Environment(UninstallModel.self) private var model
    @State private var dropTargeted = false

    var body: some View {
        @Bindable var model = model
        HSplitView {
            AppListPane()
                .frame(minWidth: 250, idealWidth: 290, maxWidth: 380)
            DetailPane()
                .frame(minWidth: 380, maxWidth: .infinity)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2).padding(6)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let app = urls.first(where: { $0.pathExtension.lowercased() == "app" }) else { return false }
            model.select(url: app)
            return true
        } isTargeted: { dropTargeted = $0 }
        .alert(L("Quit \(model.selected?.name ?? "") first?", "Thoát \(model.selected?.name ?? "") trước?"),
               isPresented: $model.showQuitAlert) {
            Button(L("Quit", "Thoát")) { model.quitAndContinue() }
            Button(L("Cancel", "Huỷ"), role: .cancel) {}
        } message: {
            Text(L("The app is running. Pinax asks it to quit, then moves it to the Trash.",
                   "App đang chạy. Pinax sẽ yêu cầu nó thoát rồi mới chuyển vào Thùng rác."))
        }
        .alert(L("Can't move this app", "Không chuyển được app này"), isPresented: $model.showSystemOwnedAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(L("Pinax can't move this app (owned by the system). Drag it to the Trash in Finder.",
                   "Pinax không chuyển được app này (thuộc quyền hệ thống). Hãy kéo nó vào Thùng rác trong Finder."))
        }
        .sheet(isPresented: Binding(get: { model.confirmCandidates != nil },
                                    set: { if !$0 { model.cancelConfirm() } })) {
            let items = model.confirmCandidates ?? []
            ConfirmSheet(items: items, bytes: items.reduce(0) { $0 + $1.size }) {
                model.confirmUninstall()
            } onCancel: {
                model.cancelConfirm()
            }
        }
        .onAppear { model.loadAppsIfNeeded() }
    }
}

// MARK: - Trái: danh sách app

private struct AppListPane: View {
    @Environment(UninstallModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                TextField(L("Search apps", "Tìm app"), text: $model.search)
                    .textFieldStyle(.roundedBorder)
                Picker(L("Sort by", "Sắp theo"), selection: $model.sort) {
                    ForEach(UninstallSort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding(12)
            Divider()
            if model.isLoadingApps && model.apps.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(get: { model.selected?.id },
                                        set: { id in model.select(model.apps.first { $0.id == id }) })) {
                    ForEach(model.visibleApps) { app in
                        AppRow(app: app).tag(app.id)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

private struct AppRow: View {
    @Environment(UninstallModel.self) private var model
    let app: UninstallApp

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: IconCache.shared.icon(forPath: app.url.path, size: 32))
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                HStack(spacing: 6) {
                    Text(model.sizes[app.id].map(fmtBytes) ?? "…").monospacedDigit()
                    Text("·")
                    Text(model.lastUsed[app.id].map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .task { model.requestMeta([app]) }
    }
}

// MARK: - Phải: những gì app để lại

private struct DetailPane: View {
    @Environment(UninstallModel.self) private var model
    @State private var focusedRow: String?
    @State private var quickLookURL: URL?
    @FocusState private var listFocused: Bool

    var body: some View {
        Group {
            if let app = model.selected {
                VStack(spacing: 0) {
                    header(app).padding(20)
                    Divider()
                    if model.isLoadingFootprint {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        footprintList
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) { footer }
            } else {
                ContentUnavailableView {
                    Label(L("Select an app to see what it leaves behind",
                            "Chọn một app để xem nó để lại những gì"), systemImage: "xmark.app")
                } description: {
                    Text(L("You can also drop an app here. Everything goes to the Trash and can be undone.",
                           "Bạn cũng có thể thả app vào đây. Mọi thứ đều vào Thùng rác và hoàn tác được."))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.selected?.id) { focusedRow = nil; quickLookURL = nil }
    }

    private func header(_ app: UninstallApp) -> some View {
        HStack(spacing: 16) {
            Image(nsImage: IconCache.shared.icon(forPath: app.url.path, size: 64))
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name).font(.title2.weight(.semibold))
                if let v = app.version {
                    Text(L("Version \(v)", "Phiên bản \(v)")).foregroundStyle(.secondary)
                }
                if let id = app.app.bundleID {
                    Text(id).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
                Text(abbreviate(app.url)).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
        }
    }

    private var footprintList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(model.rows) { row in
                    FootprintRowView(row: row, focused: focusedRow == row.id) {
                        focusedRow = row.id
                        listFocused = true
                    }
                    if row.id != model.rows.last?.id { Divider().padding(.leading, 44) }
                }
            }
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.separator.opacity(0.6)))
            .padding(20)
        }
        .focusable()
        .focused($listFocused)
        .focusEffectDisabled()
        .onKeyPress(.space) {
            guard let id = focusedRow, let row = model.rows.first(where: { $0.id == id }) else { return .ignored }
            quickLookURL = quickLookURL == nil ? row.url : nil
            return .handled
        }
        .quickLookPreview($quickLookURL)
    }

    private var footer: some View {
        HStack {
            Text(model.tickedRows.isEmpty
                 ? L("Nothing selected", "Chưa chọn gì")
                 : L("\(itemsText(model.tickedRows.count)) selected · \(fmtBytes(model.tickedBytes))",
                     "Đã chọn \(itemsText(model.tickedRows.count)) · \(fmtBytes(model.tickedBytes))"))
                .foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            if model.isBusy { ProgressView().controlSize(.small) }
            Button {
                model.uninstall()
            } label: {
                Text(L("Move to Trash", "Chuyển vào Thùng rác"))
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canUninstall)
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

private struct FootprintRowView: View {
    @Environment(UninstallModel.self) private var model
    let row: FootprintRow
    let focused: Bool
    let onFocus: () -> Void

    var body: some View {
        let on = model.ticked.contains(row.id)
        HStack(spacing: 12) {
            Button { model.toggle(row) } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square")
                    .foregroundStyle(on ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .padding(.leading, 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 6) {
                    Text(locationText)
                    if let badge = badgeText {
                        Text(badge)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(fmtBytes(row.size)).monospacedDigit().foregroundStyle(.secondary)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([row.url])
            } label: { Image(systemName: "magnifyingglass.circle") }
            .buttonStyle(.borderless)
            .help(L("Show in Finder", "Hiện trong Finder"))
            .padding(.trailing, 12)
        }
        .padding(.vertical, 7)
        .background(focused ? Color.accentColor.opacity(0.15) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
    }

    private var locationText: String {
        row.isApp ? L("Application", "Ứng dụng") : row.location
    }

    private var badgeText: String? {
        switch row.match {
        case .name: L("Matched by name", "Khớp theo tên")
        case .helper: L("Helper", "Thành phần phụ")
        case .teamGroup:
            model.sharedTeam ? L("Shared with apps from the same developer", "Dùng chung với app cùng nhà phát triển")
                             : L("App group", "Nhóm app")
        case .bundleID, .none: nil
        }
    }
}
