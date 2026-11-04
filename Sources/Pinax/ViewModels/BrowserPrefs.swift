import Foundation
import Observation
import PinaxCore

/// Tuỳ chọn trình duyệt dùng chung mọi cửa sổ (lưu UserDefaults).
@MainActor @Observable
final class BrowserPrefs {
    static let hiddenKey = "pinax.browser.showHidden"
    static let sortKey = "pinax.browser.sortKey"
    static let ascendingKey = "pinax.browser.sortAscending"
    static let foldersFirstKey = "pinax.browser.foldersFirst"
    static let lastFolderKey = "pinax.browser.lastFolder"

    var showHidden: Bool {
        didSet { UserDefaults.standard.set(showHidden, forKey: Self.hiddenKey) }
    }

    var sort: FileSort {
        didSet {
            let ud = UserDefaults.standard
            ud.set(sort.key.rawValue, forKey: Self.sortKey)
            ud.set(sort.ascending, forKey: Self.ascendingKey)
            ud.set(sort.foldersFirst, forKey: Self.foldersFirstKey)
        }
    }

    init() {
        let ud = UserDefaults.standard
        showHidden = ud.bool(forKey: Self.hiddenKey)
        sort = FileSort(
            key: FileSort.Key(rawValue: ud.string(forKey: Self.sortKey) ?? "") ?? .name,
            ascending: ud.object(forKey: Self.ascendingKey) as? Bool ?? true,
            foldersFirst: ud.object(forKey: Self.foldersFirstKey) as? Bool ?? true)
    }

    var lastFolder: String? { UserDefaults.standard.string(forKey: Self.lastFolderKey) }

    func rememberFolder(_ url: URL) { UserDefaults.standard.set(url.path, forKey: Self.lastFolderKey) }
}
