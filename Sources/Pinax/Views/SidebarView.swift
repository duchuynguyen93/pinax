import SwiftUI
import AppKit
import PinaxCore

enum SidebarItem: Hashable {
    case favorite(URL)
    case volume(URL)
    case pinax(SidebarSection)
    case workspace(UUID)
}

/// Sidebar ba nhóm: Favorites, Locations, Pinax.
struct SidebarView: View {
    let model: BrowserModel
    @Environment(FavoritesModel.self) private var favorites
    @Environment(VolumesModel.self) private var volumes
    @Environment(AppEnvironment.self) private var env
    /// Favorite đang được rê file tới (để tô sáng).
    @State private var dropTarget: URL?

    private var selection: Binding<SidebarItem?> {
        Binding(
            get: {
                if let s = model.pinax { return .pinax(s) }
                if let f = favorites.urls.first(where: { $0.path == model.folder.path }) { return .favorite(f) }
                if let v = volumes.volumes.first(where: { $0.url.path == model.folder.path }) { return .volume(v.url) }
                return nil
            },
            set: { item in
                switch item {
                case .favorite(let url), .volume(let url): model.navigate(to: url)
                case .pinax(let s): model.showPinax(s)
                case .workspace(let id):
                    if let w = env.workspaces.items.first(where: { $0.id == id }) { OpenRouter.shared.openWorkspace(w) }
                case nil: break
                }
            })
    }

    var body: some View {
        List(selection: selection) {
            Section(L("Favorites", "Yêu thích")) {
                ForEach(favorites.urls, id: \.self) { url in
                    Label {
                        Text(FileManager.default.displayName(atPath: url.path))
                    } icon: {
                        Image(systemName: Self.symbol(for: url))
                    }
                    .tag(SidebarItem.favorite(url))
                    .listRowBackground(dropTarget == url ? Color.accentColor.opacity(0.3) : nil)
                    .dropDestination(for: URL.self) { urls, _ in drop(urls, onto: url) } isTargeted: { on in
                        if on { dropTarget = url } else if dropTarget == url { dropTarget = nil }
                    }
                    .contextMenu {
                        Button(L("Remove from Favorites", "Bỏ khỏi Yêu thích")) { favorites.remove(url) }
                        addCurrentButton
                    }
                }
                .onMove { favorites.move(from: $0, to: $1) }
            }
            Section(L("Locations", "Vị trí")) {
                ForEach(volumes.volumes) { v in
                    HStack {
                        Label(v.name, systemImage: v.isRoot ? "internaldrive" : "externaldrive")
                        if v.canEject {
                            Spacer()
                            Button { volumes.eject(v) } label: { Image(systemName: "eject.fill") }
                                .buttonStyle(.borderless)
                                .help(L("Eject", "Đẩy ra"))
                                .accessibilityLabel(L("Eject", "Đẩy ra"))
                        }
                    }
                    .tag(SidebarItem.volume(v.url))
                }
            }
            if !env.workspaces.items.isEmpty {
                Section(L("Workspaces", "Workspace")) {
                    ForEach(env.workspaces.items) { ws in
                        Label(ws.name, systemImage: "rectangle.stack")
                            .tag(SidebarItem.workspace(ws.id))
                            .help(ws.tabs.map { FileManager.default.displayName(atPath: $0.left) }.joined(separator: "\n"))
                            .contextMenu { workspaceMenu(ws) }
                    }
                }
            }
            Section("Pinax") {
                ForEach(SidebarSection.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(SidebarItem.pinax(s))
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu { addCurrentButton }
    }

    @ViewBuilder private func workspaceMenu(_ ws: Workspace) -> some View {
        Button(L("Open", "Mở")) { OpenRouter.shared.openWorkspace(ws) }
        Button(L("Rename…", "Đổi tên…")) {
            NamePrompt.ask(title: L("Rename Workspace", "Đổi tên workspace"), message: "", initial: ws.name,
                           confirm: L("Rename", "Đổi tên"), window: model.window) { env.workspaces.rename(ws.id, to: $0) }
        }
        Button(L("Update from Current Window", "Cập nhật từ cửa sổ hiện tại")) {
            if let w = model.window {
                let tabs = WindowRegistry.shared.tabStates(for: w)
                if !tabs.isEmpty { env.workspaces.update(ws.id, tabs: tabs) }
            }
        }
        Button(L("Delete", "Xoá")) {
            env.workspaces.delete(ws.id)
            env.toast.show(L("Workspace deleted", "Đã xoá workspace"))
        }
    }

    /// Thả file lên Favorite: ⌥ = chép, ⌘ = chuyển, mặc định theo ổ đĩa. Qua TransferQueue.
    private func drop(_ urls: [URL], onto dest: URL) -> Bool {
        let flags = NSEvent.modifierFlags
        let mask: NSDragOperation = flags.contains(.option) ? [.copy] : flags.contains(.command) ? [.move] : [.copy, .move, .generic]
        guard let kind = model.dropKind(sources: urls.filter(\.isFileURL), destination: dest, mask: mask) else { return false }
        model.performDrop(sources: urls.filter(\.isFileURL), destination: dest, kind: kind)
        return true
    }

    private var addCurrentButton: some View {
        Button(L("Add Current Folder to Favorites", "Thêm thư mục hiện tại vào Yêu thích")) {
            favorites.add(model.folder)
        }
        .disabled(model.pinax != nil || favorites.contains(model.folder))
    }

    private static func symbol(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        switch url.path {
        case home: return "house"
        case "\(home)/Desktop": return "menubar.dock.rectangle"
        case "\(home)/Documents": return "doc"
        case "\(home)/Downloads": return "arrow.down.circle"
        case "/Applications": return "square.grid.2x2"
        case "\(home)/Library/Mobile Documents/com~apple~CloudDocs": return "icloud"
        default: return "folder"
        }
    }
}
