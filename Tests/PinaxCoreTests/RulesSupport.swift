import Foundation
@testable import PinaxCore

/// lastUsed / dateAdded cố định theo đường dẫn; thiếu = nil (không biết).
struct RuleFixedLastUsed: LastUsedProvider {
    var map: [String: LastUsedInfo] = [:]

    func info(for url: URL) -> LastUsedInfo {
        map[url.resolvingSymlinksInPath().standardizedFileURL.path] ?? LastUsedInfo()
    }

    mutating func set(_ url: URL, lastUsed: Date? = nil, dateAdded: Date? = nil) {
        map[url.resolvingSymlinksInPath().standardizedFileURL.path] = LastUsedInfo(lastUsed: lastUsed, dateAdded: dateAdded)
    }
}

struct RuleFakeInstalledApps: InstalledAppsProvider {
    var apps: [InstalledApp] = []
    func installedApps() -> [InstalledApp] { apps }
}

struct NoSpotlight: SpotlightSearching {
    func find(query: String, in root: URL) -> [URL]? { nil }
}

struct FixedSpotlight: SpotlightSearching {
    let urls: [URL]
    func find(query: String, in root: URL) -> [URL]? { urls }
}

struct NoMountedImages: MountedImagesProviding {
    var paths: Set<URL> = []
    func imagePaths() -> Set<URL> { paths }
}

struct StubRule: CleanRule {
    let id: String
    let group = RuleGroup.safe
    let title = "stub"
    let urls: [URL]
    func scan(_ ctx: ScanContext) async -> RuleResult {
        RuleResult(ruleID: id, candidates: urls.map {
            Candidate(url: $0, size: 1, fingerprint: FileFingerprint.read(from: $0)!, reason: id, lastUsed: nil, preselected: false)
        }, status: .ok)
    }
}

let testNow = Date(timeIntervalSince1970: 1_800_000_000)

func daysBefore(_ d: Int) -> Date { testNow.addingTimeInterval(-Double(d) * 86_400) }

extension Sandbox {
    func context(lastUsed: RuleFixedLastUsed = RuleFixedLastUsed(), apps: [InstalledApp] = [],
                 settings: ((inout CleanSettings) -> Void)? = nil) -> ScanContext {
        var s = CleanSettings.defaults(home: home)
        settings?(&s)
        return ScanContext(home: home, applicationRoots: [self.apps], now: testNow, lastUsed: lastUsed,
                           installedApps: RuleFakeInstalledApps(apps: apps), settings: s)
    }

    /// Ghi file với nội dung xác định (cùng seed = cùng nội dung).
    @discardableResult
    func writeFilled(_ name: String, in dir: URL? = nil, bytes: Int, seed: UInt8) throws -> URL {
        let url = (dir ?? downloads).appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: seed, count: bytes).write(to: url)
        return url
    }

    func fakeApp(_ name: String, bundleID: String?) throws -> InstalledApp {
        let url = apps.appendingPathComponent("\(name).app", isDirectory: true)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2048).write(to: url.appendingPathComponent("Contents/blob"))
        return InstalledApp(url: url, bundleID: bundleID, name: name)
    }
}

func paths(_ r: RuleResult) -> Set<String> { Set(r.candidates.map { $0.url.lastPathComponent }) }
