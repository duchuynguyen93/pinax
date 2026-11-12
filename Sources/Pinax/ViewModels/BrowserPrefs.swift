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
    static let previewKey = "pinax.browser.preview"
    static let groupByKey = "pinax.browser.groupBy"
    /// Đổi kiểu nhóm → mọi `BrowserModel` (mọi cửa sổ / pane) dựng lại danh sách.
    static let groupingChanged = Notification.Name("pinax.browser.groupingChanged")

    var showHidden: Bool {
        didSet { UserDefaults.standard.set(showHidden, forKey: Self.hiddenKey) }
    }

    var showPreview: Bool {
        didSet { UserDefaults.standard.set(showPreview, forKey: Self.previewKey) }
    }

    var groupBy: GroupBy {
        didSet {
            UserDefaults.standard.set(groupBy.rawValue, forKey: Self.groupByKey)
            NotificationCenter.default.post(name: Self.groupingChanged, object: nil)
        }
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
        // PINAX_QA_PREVIEW=1 (QA): bật xem trước mà không ghi đè tuỳ chọn đã lưu.
        showPreview = ud.bool(forKey: Self.previewKey) || ProcessInfo.processInfo.environment["PINAX_QA_PREVIEW"] == "1"
        // PINAX_QA_GROUP=kind|modified (QA): bắt đầu với kiểu nhóm đó mà không ghi đè tuỳ chọn đã lưu
        // (gán trong init không kích hoạt didSet).
        groupBy = ProcessInfo.processInfo.environment["PINAX_QA_GROUP"].flatMap(GroupBy.init(rawValue:))
            ?? GroupBy(rawValue: ud.string(forKey: Self.groupByKey) ?? "") ?? .none
        sort = FileSort(
            key: FileSort.Key(rawValue: ud.string(forKey: Self.sortKey) ?? "") ?? .name,
            ascending: ud.object(forKey: Self.ascendingKey) as? Bool ?? true,
            foldersFirst: ud.object(forKey: Self.foldersFirstKey) as? Bool ?? true)
    }

    var lastFolder: String? { UserDefaults.standard.string(forKey: Self.lastFolderKey) }

    func rememberFolder(_ url: URL) { UserDefaults.standard.set(url.path, forKey: Self.lastFolderKey) }
}
