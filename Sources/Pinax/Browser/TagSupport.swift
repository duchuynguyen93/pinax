import AppKit
import PinaxCore

/// Một trong 7 tag màu chuẩn của macOS.
struct StandardTag: Identifiable {
    let index: Int
    let name: String
    let color: NSColor
    var id: Int { index }
}

/// Tag màu của Finder: danh sách, ảnh chấm cho menu, đọc / ghi tag. Tag là metadata nên không qua Executor / journal
/// (không đổi nội dung hay vị trí file; bấm lại là bỏ).
enum TagSupport {
    /// Chỉ số trong `NSWorkspace.fileLabels` theo thứ tự Finder: Red, Orange, Yellow, Green, Blue, Purple, Gray.
    private static let order = [6, 7, 5, 2, 4, 3, 1]

    @MainActor static var standard: [StandardTag] {
        let ws = NSWorkspace.shared
        let names = ws.fileLabels, colors = ws.fileLabelColors
        return order.compactMap { i in
            guard i < names.count, i < colors.count else { return nil }
            return StandardTag(index: i, name: names[i], color: colors[i])
        }
    }

    @MainActor private static var colorByName: [String: NSColor] = [:]

    /// Màu chấm của tag: 7 tag chuẩn theo tên, tên khác → xám.
    @MainActor static func color(forTagNamed raw: String) -> NSColor {
        if colorByName.isEmpty { for t in standard { colorByName[t.name] = t.color } }
        // Tên có thể mang hậu tố "\n<số màu>" khi đọc thô.
        let name = raw.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? raw
        return colorByName[name] ?? .systemGray
    }

    /// Chấm màu cho mục menu / sidebar.
    static func dot(_ color: NSColor, size: CGFloat = 12) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            let path = NSBezierPath(ovalIn: r.insetBy(dx: 1, dy: 1))
            color.setFill()
            path.fill()
            color.shadow(withLevel: 0.25)?.setStroke()
            path.lineWidth = 1
            path.stroke()
            return true
        }
        img.isTemplate = false
        return img
    }

    static func tags(of url: URL) -> [String] {
        var u = url
        u.removeAllCachedResourceValues()
        return (try? u.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
    }

    /// Thêm / bỏ tag `name` ở mọi URL (ngoài main). Trả số mục lỗi.
    nonisolated static func apply(_ name: String, add: Bool, to urls: [URL]) -> Int {
        var failed = 0
        for url in urls {
            var tags = Self.tags(of: url)
            if add {
                guard !tags.contains(name) else { continue }
                tags.append(name)
            } else {
                guard tags.contains(name) else { continue }
                tags.removeAll { $0 == name }
            }
            do { try (url as NSURL).setResourceValue(tags, forKey: .tagNamesKey) } catch { failed += 1 }
        }
        return failed
    }

    /// Spotlight: mọi file mang tag này.
    static func predicate(for name: String) -> NSPredicate {
        NSPredicate(format: "kMDItemUserTags == %@", name)
    }
}
