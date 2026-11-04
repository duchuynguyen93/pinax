import Foundation
import Observation

/// Danh sách Favorites của sidebar: thêm / bỏ / sắp xếp lại, lưu UserDefaults.
@MainActor @Observable
final class FavoritesModel {
    static let key = "pinax.favorites"

    private(set) var urls: [URL]

    init() {
        if let paths = UserDefaults.standard.stringArray(forKey: Self.key) {
            urls = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        } else {
            urls = Self.defaults()
        }
    }

    static func defaults() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var list = [home] + ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0, isDirectory: true) }
        list.append(URL(fileURLWithPath: "/Applications", isDirectory: true))
        let icloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        if FileManager.default.fileExists(atPath: icloud.path) { list.append(icloud) }
        return list
    }

    func contains(_ url: URL) -> Bool { urls.contains { $0.path == url.path } }

    func add(_ url: URL) {
        guard !contains(url) else { return }
        urls.append(URL(fileURLWithPath: url.path, isDirectory: true))
        save()
    }

    func remove(_ url: URL) {
        urls.removeAll { $0.path == url.path }
        save()
    }

    func move(from source: IndexSet, to destination: Int) {
        urls.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() { UserDefaults.standard.set(urls.map(\.path), forKey: Self.key) }
}
