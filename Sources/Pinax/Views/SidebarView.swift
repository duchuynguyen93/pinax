import SwiftUI
import AppKit

enum SidebarItem: Hashable {
    case favorite(URL)
    case volume(URL)
    case pinax(SidebarSection)
}

/// Sidebar ba nhóm: Favorites, Locations, Pinax.
struct SidebarView: View {
    let model: BrowserModel
    @Environment(FavoritesModel.self) private var favorites
    @Environment(VolumesModel.self) private var volumes
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
            Section("Pinax") {
                ForEach(SidebarSection.allCases) { s in
                    Label(s.title, systemImage: s.symbol).tag(SidebarItem.pinax(s))
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu { addCurrentButton }
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
