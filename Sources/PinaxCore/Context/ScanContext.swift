import Foundation

public struct CleanSettings: Codable, Equatable, Sendable {
    public var largeFileMB: Int = 500
    public var oldDownloadDays: Int = 90
    public var unusedAppDays: Int = 180
    public var screenRecordingDays: Int = 30
    public var staleProjectDays: Int = 180
    public var projectRoots: [URL]
    public var tidyFolder: URL

    public init(largeFileMB: Int = 500, oldDownloadDays: Int = 90, unusedAppDays: Int = 180,
                screenRecordingDays: Int = 30, staleProjectDays: Int = 180,
                projectRoots: [URL], tidyFolder: URL) {
        self.largeFileMB = largeFileMB
        self.oldDownloadDays = oldDownloadDays
        self.unusedAppDays = unusedAppDays
        self.screenRecordingDays = screenRecordingDays
        self.staleProjectDays = staleProjectDays
        self.projectRoots = projectRoots
        self.tidyFolder = tidyFolder
    }

    /// Mặc định: projectRoots là các thư mục `~/Code`, `~/Developer`, `~/Projects` nếu tồn tại.
    public static func defaults(home: URL) -> CleanSettings {
        let roots = ["Code", "Developer", "Projects"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
            .filter { var isDir: ObjCBool = false
                      return FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue }
        return CleanSettings(projectRoots: roots,
                             tidyFolder: home.appendingPathComponent("Downloads", isDirectory: true))
    }
}

/// Thông tin dùng gần nhất. nil = KHÔNG BIẾT, không bao giờ suy ra "lâu không dùng" từ nil (§1.9).
public struct LastUsedInfo: Equatable, Sendable {
    public var lastUsed: Date?
    public var dateAdded: Date?

    public init(lastUsed: Date? = nil, dateAdded: Date? = nil) {
        self.lastUsed = lastUsed
        self.dateAdded = dateAdded
    }
}

public protocol LastUsedProvider: Sendable {
    func info(for url: URL) -> LastUsedInfo
}

public struct InstalledApp: Hashable, Sendable {
    public let url: URL
    public let bundleID: String?
    public let name: String

    public init(url: URL, bundleID: String?, name: String) {
        self.url = url
        self.bundleID = bundleID
        self.name = name
    }
}

public protocol InstalledAppsProvider: Sendable {
    func installedApps() -> [InstalledApp]
}

public struct ScanContext: Sendable {
    /// Test: thư mục tạm giả làm home.
    public var home: URL
    /// /Applications, ~/Applications
    public var applicationRoots: [URL]
    public var now: Date
    public var lastUsed: LastUsedProvider
    public var installedApps: InstalledAppsProvider
    public var settings: CleanSettings

    public init(home: URL, applicationRoots: [URL], now: Date = Date(),
                lastUsed: LastUsedProvider, installedApps: InstalledAppsProvider,
                settings: CleanSettings) {
        self.home = home
        self.applicationRoots = applicationRoots
        self.now = now
        self.lastUsed = lastUsed
        self.installedApps = installedApps
        self.settings = settings
    }
}
