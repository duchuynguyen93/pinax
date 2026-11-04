import Foundation

/// File con của `~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads`.
/// Không đủ quyền → `.needsFullDiskAccess`.
public struct MailDownloadsRule: CleanRule {
    public let id = "mailDownloads"
    public let group = RuleGroup.safe
    public let title = "Mail attachments cache"

    public init() {}

    public func scan(_ ctx: ScanContext) async -> RuleResult {
        RuleKit.run(id) {
            let dir = ctx.home.appendingPathComponent(
                "Library/Containers/com.apple.mail/Data/Library/Mail Downloads", isDirectory: true)
            let children: [URL]
            do {
                children = try RuleKit.children(of: dir)
            } catch {
                if RuleKit.isPermissionError(error) { return ([], .needsFullDiskAccess) }
                if RuleKit.isNoSuchFile(error) { return ([], .ok) }
                return ([], .failed(error.localizedDescription))
            }
            let guardian = ctx.pathGuard
            var out: [Candidate] = []
            for url in children {
                try Task.checkCancellation()
                guard let meta = FileMeta.read(url), !meta.isSymlink, !meta.isICloudPlaceholder else { continue }
                if let c = try RuleKit.makeCandidate(url, ctx: ctx, guardian: guardian,
                                                     reason: "Mail attachment copy",
                                                     kind: .mailAttachment,
                                                     lastUsed: ctx.lastUsed.info(for: url).lastUsed, preselected: true) {
                    out.append(c)
                }
            }
            return (out, .ok)
        }
    }
}
