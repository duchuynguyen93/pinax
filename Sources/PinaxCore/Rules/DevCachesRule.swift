import Foundation

/// Cache công cụ dev: danh sách cứng, mỗi thư mục tồn tại và ≥ ngưỡng = 1 candidate.
public struct DevCachesRule: CleanRule {
    public let id = "devCaches"
    public let group = RuleGroup.safe
    public let title = "Developer caches"
    public var minBytes: Int64

    public init(minBytes: Int64 = 10 * 1_048_576) { self.minBytes = minBytes }

    static let locations: [(path: String, name: String)] = [
        ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData"),
        ("Library/Developer/CoreSimulator/Caches", "CoreSimulator caches"),
        ("Library/Caches/Homebrew", "Homebrew cache"),
        (".npm/_cacache", "npm cache"),
        ("Library/Caches/pip", "pip cache"),
        ("Library/Caches/Yarn", "Yarn cache"),
        ("Library/Caches/CocoaPods", "CocoaPods cache"),
        ("Library/Caches/org.swift.swiftpm", "SwiftPM cache"),
        (".gradle/caches", "Gradle caches"),
    ]

    public func scan(_ ctx: ScanContext) async -> RuleResult {
        RuleKit.run(id) {
            let guardian = ctx.pathGuard
            var out: [Candidate] = []
            for loc in Self.locations {
                try Task.checkCancellation()
                let url = ctx.home.appendingPathComponent(loc.path, isDirectory: true)
                guard let meta = FileMeta.read(url), meta.isDirectory, !meta.isSymlink else { continue }
                guard let c = try RuleKit.makeCandidate(url, ctx: ctx, guardian: guardian,
                                                        reason: "Rebuildable cache: \(loc.name)",
                                                        kind: .devCache(loc.name), lastUsed: nil, preselected: true),
                      c.size >= minBytes else { continue }
                out.append(c)
            }
            return (out, .ok)
        }
    }
}
