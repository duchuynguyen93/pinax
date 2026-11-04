import Foundation
import CoreServices

/// `kMDItemLastUsedDate` / `kMDItemDateAdded` qua MDItem (đồng bộ, không cần runloop). Thiếu → nil (= không biết).
public struct SpotlightLastUsedProvider: LastUsedProvider {
    public init() {}

    public func info(for url: URL) -> LastUsedInfo {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return LastUsedInfo() }
        let used = MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
        let added = MDItemCopyAttribute(item, kMDItemDateAdded) as? Date
        return LastUsedInfo(lastUsed: used, dateAdded: added)
    }
}
