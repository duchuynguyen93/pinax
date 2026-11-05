import Foundation

/// Mục trong ~/Library mang bundle id của app không còn cài (M4 §3). Không đọc Containers / Group Containers.
public struct LeftoversRule: CleanRule {
    public let id = "leftovers"
    public let group = RuleGroup.review
    public let title = "App leftovers"

    private let isKnownToLaunchServices: InstalledBundleIndex.LaunchServicesLookup
    private let spotlightApps: SpotlightInstalledApps.Provider
    private let binDirs: [URL]?

    /// `binDirs` nil = danh sách mặc định tính từ `ctx.home`.
    public init(isKnownToLaunchServices: @escaping InstalledBundleIndex.LaunchServicesLookup = InstalledBundleIndex.defaultLaunchServices,
                spotlightApps: @escaping SpotlightInstalledApps.Provider = SpotlightInstalledApps.defaultProvider,
                binDirs: [URL]? = nil) {
        self.isKnownToLaunchServices = isKnownToLaunchServices
        self.spotlightApps = spotlightApps
        self.binDirs = binDirs
    }

    public func scan(_ ctx: ScanContext) async -> RuleResult {
        RuleKit.run(id) {
            let guardian = ctx.pathGuard
            let library = ctx.home.appendingPathComponent("Library", isDirectory: true)
            let index = InstalledBundleIndex(apps: ctx.installedApps.installedApps() + spotlightApps(),
                                             launchServices: isKnownToLaunchServices)
            let tokens = LeftoverGuards.nameTokens(of: index.apps)
            let bins = binDirs ?? LeftoverGuards.defaultBinDirs(home: ctx.home)
            let cutoff = RuleKit.daysAgo(ctx.settings.leftoverDays, from: ctx.now)
            let pinax = PathGuard.pinaxBundleID.lowercased()
            var out: [Candidate] = []
            for loc in AppFootprint.idLocations {
                for (name, url) in AppFootprint.entries(library, loc) {
                    try Task.checkCancellation()
                    guard let bid = AppFootprint.bundleIDFromEntryName(name, in: loc) else { continue }
                    let lower = bid.lowercased()
                    if PathGuard.isProtectedApp(bundleID: bid) || lower.hasPrefix(pinax) { continue }
                    if index.isInstalled(bid) { continue }
                    if LeftoverGuards.isDenylisted(bid) { continue }
                    if LeftoverGuards.vendorMatches(bid, installedIDs: index.ids) { continue }
                    if LeftoverGuards.nameTokenMatches(bid, tokens: tokens) { continue }
                    if LeftoverGuards.isCLITool(bid, binDirs: bins) { continue }
                    guard let meta = FileMeta.read(url), !meta.isSymlink, !meta.isICloudPlaceholder,
                          let modified = meta.modified, modified < cutoff else { continue }
                    if loc == "LaunchAgents", !Self.programIsMissing(url) { continue }
                    if loc == "Application Support", LeftoverGuards.hasRecentContent(url, since: cutoff) { continue }
                    if let c = try RuleKit.makeCandidate(url, ctx: ctx, guardian: guardian, reason: "Left by \(bid)",
                                                         kind: .leftover(bundleID: bid), lastUsed: nil, preselected: false) {
                        out.append(c)
                    }
                }
            }
            return (out, .ok)
        }
    }

    /// true chỉ khi đọc được plist, có Program / ProgramArguments[0] và file đó không còn.
    static func programIsMissing(_ plist: URL) -> Bool {
        guard let data = try? Data(contentsOf: plist),
              let obj = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dict = obj as? [String: Any] else { return false }
        let program = (dict["Program"] as? String) ?? (dict["ProgramArguments"] as? [String])?.first
        guard let program, !program.isEmpty else { return false }
        return !FileManager.default.fileExists(atPath: (program as NSString).expandingTildeInPath)
    }
}
