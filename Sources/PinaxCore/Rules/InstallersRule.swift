import Foundation

/// `.dmg` / `.pkg` / `.zip` cấp 1 trong Downloads và Desktop có tên khớp một app đã cài.
/// `.dmg` / `.pkg` tick sẵn, `.zip` không. Bỏ DMG đang mount.
public struct InstallersRule: CleanRule {
    public let id = "installers"
    public let group = RuleGroup.safe
    public let title = "Installers of installed apps"
    public let mounted: MountedImagesProviding

    public init(mounted: MountedImagesProviding = MountedImages()) { self.mounted = mounted }

    static let noiseTokens = ["universal", "arm64", "x64", "intel", "mac", "macos", "osx", "setup", "installer", "latest"]
    private static let versionRegex = try! NSRegularExpression(pattern: #"\d+(\.\d+)*"#)
    private static let tokenRegex = try! NSRegularExpression(
        pattern: #"(?<![a-z0-9])("# + noiseTokens.joined(separator: "|") + #")(?![a-z0-9])"#)

    /// Chuẩn hoá: lowercase, bỏ version, bỏ token nhiễu, bỏ mọi ký tự không phải chữ/số.
    static func normalize(_ name: String) -> String {
        var s = name.lowercased()
        for regex in [versionRegex, tokenRegex] {
            s = regex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }
        return String(s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(Character.init))
    }

    /// Khớp nếu bằng nhau, hoặc tên app (≥ 4 ký tự) là tiền tố của tên installer.
    static func matches(installer: String, app: String) -> Bool {
        guard !installer.isEmpty, !app.isEmpty else { return false }
        return installer == app || (app.count >= 4 && installer.hasPrefix(app))
    }

    public func scan(_ ctx: ScanContext) async -> RuleResult {
        RuleKit.run(id) {
            let guardian = ctx.pathGuard
            let apps = ctx.installedApps.installedApps().map { app -> (name: String, keys: Set<String>) in
                let fileBase = app.url.deletingPathExtension().lastPathComponent
                return (app.name, Set([Self.normalize(app.name), Self.normalize(fileBase)]).filter { !$0.isEmpty })
            }
            let mountedPaths = Set(mounted.imagePaths().map { RuleKit.resolvedPath($0).lowercased() })
            var out: [Candidate] = []

            for dirName in ["Downloads", "Desktop"] {
                let dir = ctx.home.appendingPathComponent(dirName, isDirectory: true)
                for url in (try? RuleKit.children(of: dir)) ?? [] {
                    try Task.checkCancellation()
                    let ext = url.pathExtension.lowercased()
                    guard ["dmg", "pkg", "zip"].contains(ext) else { continue }
                    guard let meta = FileMeta.read(url), meta.isRegular, !meta.isSymlink, !meta.isICloudPlaceholder else { continue }
                    if ext == "dmg" && mountedPaths.contains(RuleKit.resolvedPath(url).lowercased()) { continue }
                    let installerKey = Self.normalize(url.deletingPathExtension().lastPathComponent)
                    guard let app = apps.first(where: { a in a.keys.contains { Self.matches(installer: installerKey, app: $0) } })
                    else { continue }
                    if let c = try RuleKit.makeCandidate(url, ctx: ctx, guardian: guardian,
                                                         reason: "Installer of installed app \(app.name)",
                                                         kind: .installedApp(app.name),
                                                         lastUsed: ctx.lastUsed.info(for: url).lastUsed,
                                                         preselected: ext != "zip") {
                        out.append(c)
                    }
                }
            }
            return (out, .ok)
        }
    }
}
