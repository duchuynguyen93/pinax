import Foundation
import CoreServices

/// Tập bundle id của app đang cài: quét roots (qua `InstalledApp`) + hỏi LaunchServices (tiêm được để test).
public struct InstalledBundleIndex: Sendable {
    public typealias LaunchServicesLookup = @Sendable (String) -> Bool

    /// Mọi app đã biết (roots + Spotlight), dùng cho vendor / tên.
    public let apps: [InstalledApp]
    public let ids: [String]
    private let idSet: Set<String>
    private let launchServices: LaunchServicesLookup

    public init(apps: [InstalledApp], launchServices: @escaping LaunchServicesLookup = InstalledBundleIndex.defaultLaunchServices) {
        self.apps = apps
        let lowered = apps.compactMap { $0.bundleID?.lowercased() }.filter { !$0.isEmpty }
        self.ids = lowered
        self.idSet = Set(lowered)
        self.launchServices = launchServices
    }

    /// Mặc định: có URL app nào đăng ký với bundle id này không (CoreServices, không cần AppKit).
    public static let defaultLaunchServices: LaunchServicesLookup = { id in
        guard let urls = LSCopyApplicationURLsForBundleIdentifier(id as CFString, nil)?.takeRetainedValue() else { return false }
        return CFArrayGetCount(urls) > 0
    }

    /// §3.3: trùng, `id` là helper của app cài (`installed.` là tiền tố), hoặc `id` là tiền tố của app cài. Không phân biệt hoa/thường.
    public func isInstalled(_ id: String) -> Bool {
        let x = id.lowercased()
        if idSet.contains(x) { return true }
        for installed in ids {
            if x.hasPrefix(installed + ".") || installed.hasPrefix(x + ".") { return true }
        }
        return launchServices(id)
    }
}
