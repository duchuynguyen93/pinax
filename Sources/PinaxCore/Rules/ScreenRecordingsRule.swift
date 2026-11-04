import Foundation

/// `.mov` tên bắt đầu "Screen Recording" / "Bản ghi màn hình", cũ hơn N ngày theo max(lastUsed, created).
public struct ScreenRecordingsRule: CleanRule {
    public let id = "screenRecordings"
    public let group = RuleGroup.review
    public let title = "Old screen recordings"
    /// Giá trị `location` của com.apple.screencapture (có thể bắt đầu bằng `~`). Inject để test.
    public let captureLocation: @Sendable () -> String?

    public init(captureLocation: @escaping @Sendable () -> String? = {
        UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
    }) {
        self.captureLocation = captureLocation
    }

    private static let prefixes = ["Screen Recording", "Bản ghi màn hình"]
        .map { $0.precomposedStringWithCanonicalMapping.lowercased() }

    public func scan(_ ctx: ScanContext) async -> RuleResult {
        RuleKit.run(id) {
            let guardian = ctx.pathGuard
            let cutoff = RuleKit.daysAgo(ctx.settings.screenRecordingDays, from: ctx.now)
            var dirs = ["Desktop", "Documents", "Movies"].map { ctx.home.appendingPathComponent($0, isDirectory: true) }
            if let loc = captureLocation(), !loc.isEmpty {
                if loc == "~" || loc.hasPrefix("~/") {
                    dirs.append(ctx.home.appendingPathComponent(String(loc.dropFirst(2)), isDirectory: true))
                } else {
                    dirs.append(URL(fileURLWithPath: loc, isDirectory: true))
                }
            }
            var seenDirs = Set<String>(), seenFiles = Set<String>()
            var out: [Candidate] = []
            for dir in dirs where seenDirs.insert(RuleKit.resolvedPath(dir).lowercased()).inserted {
                for url in (try? RuleKit.children(of: dir)) ?? [] {
                    try Task.checkCancellation()
                    let name = url.lastPathComponent.precomposedStringWithCanonicalMapping.lowercased()
                    guard url.pathExtension.lowercased() == "mov",
                          Self.prefixes.contains(where: { name.hasPrefix($0) }),
                          seenFiles.insert(RuleKit.resolvedPath(url)).inserted,
                          let meta = FileMeta.read(url), meta.isRegular, !meta.isSymlink, !meta.isICloudPlaceholder
                    else { continue }
                    let used = ctx.lastUsed.info(for: url).lastUsed
                    guard let reference = [used, meta.created].compactMap({ $0 }).max(), reference < cutoff else { continue }
                    if let c = try RuleKit.makeCandidate(url, ctx: ctx, guardian: guardian,
                                                         reason: "Screen recording older than \(ctx.settings.screenRecordingDays) days",
                                                         kind: .screenRecording, lastUsed: used, preselected: false) {
                        out.append(c)
                    }
                }
            }
            return (out, .ok)
        }
    }
}
