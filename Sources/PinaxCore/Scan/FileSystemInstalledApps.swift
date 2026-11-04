import Foundation

/// Liệt kê `.app` trong `applicationRoots`, sâu tối đa 2 (vd `/Applications/Utilities/X.app`), không đi vào bundle.
public struct FileSystemInstalledApps: InstalledAppsProvider {
    public let roots: [URL]

    public init(roots: [URL]) { self.roots = roots }

    public func installedApps() -> [InstalledApp] {
        var apps: [InstalledApp] = []
        var seen = Set<String>()
        let walker = DirectoryWalker(maxDepth: 2)
        for root in roots {
            try? walker.walk(root) { entry in
                guard entry.url.pathExtension.lowercased() == "app", seen.insert(entry.url.path).inserted else { return true }
                let info = Bundle(url: entry.url)?.infoDictionary
                let fileName = entry.url.deletingPathExtension().lastPathComponent
                apps.append(InstalledApp(url: entry.url,
                                         bundleID: info?["CFBundleIdentifier"] as? String,
                                         name: (info?["CFBundleName"] as? String) ?? fileName))
                return true
            }
        }
        return apps
    }
}
