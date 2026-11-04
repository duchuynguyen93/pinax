import Foundation

/// App đã cài, tìm thấy qua resolver.
public struct CatalogApp: Equatable, Sendable, Identifiable {
    public var id: String { bundleID }
    public let bundleID: String
    public let url: URL
    public var name: String { url.deletingPathExtension().lastPathComponent }
}

/// Danh sách bundle id Terminal / Editor; chỉ trả app thực sự có trên máy.
/// Core không biết `NSWorkspace`: tầng app truyền closure resolve (`urlForApplication(withBundleIdentifier:)`).
public enum AppCatalog {
    public static let terminalBundleIDs: [String] = [
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
    ]

    public static let editorBundleIDs: [String] = [
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "dev.zed.Zed", "com.apple.dt.Xcode",
        "com.sublimetext.4", "com.panic.Nova", "com.barebones.bbedit",
        "com.jetbrains.intellij", "com.jetbrains.pycharm", "com.jetbrains.WebStorm", "com.google.android.studio",
    ]

    public static func installedTerminals(resolve: (String) -> URL?) -> [CatalogApp] {
        installed(terminalBundleIDs, resolve: resolve)
    }

    public static func installedEditors(resolve: (String) -> URL?) -> [CatalogApp] {
        installed(editorBundleIDs, resolve: resolve)
    }

    private static func installed(_ ids: [String], resolve: (String) -> URL?) -> [CatalogApp] {
        ids.compactMap { id in resolve(id).map { CatalogApp(bundleID: id, url: $0) } }
    }
}
