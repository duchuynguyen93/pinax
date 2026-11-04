import Foundation

/// Tóm tắt `git status --porcelain=v2 --branch`.
public struct GitSummary: Equatable, Sendable {
    /// Tên nhánh; khi detached là 7 ký tự đầu của commit (nếu biết).
    public var branch: String
    public var detached: Bool
    public var hasUpstream: Bool
    public var ahead: Int
    public var behind: Int
    /// Số mục có thay đổi đã stage (cột X).
    public var staged: Int
    /// Số mục có thay đổi chưa stage trong working tree (cột Y).
    public var modified: Int
    public var untracked: Int
    public var conflicted: Int
    /// Số file bị ảnh hưởng (mỗi file tính một lần, dù vừa staged vừa modified).
    public var changedFiles: Int

    public var isClean: Bool { changedFiles == 0 }

    public init(branch: String = "", detached: Bool = false, hasUpstream: Bool = false, ahead: Int = 0,
                behind: Int = 0, staged: Int = 0, modified: Int = 0, untracked: Int = 0,
                conflicted: Int = 0, changedFiles: Int = 0) {
        self.branch = branch
        self.detached = detached
        self.hasUpstream = hasUpstream
        self.ahead = ahead
        self.behind = behind
        self.staged = staged
        self.modified = modified
        self.untracked = untracked
        self.conflicted = conflicted
        self.changedFiles = changedFiles
    }
}

/// Parser thuần cho output porcelain v2.
public enum GitStatus {
    public static func parse(_ output: String) -> GitSummary {
        var s = GitSummary()
        var oid: String?
        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("# ") {
                let parts = line.dropFirst(2).split(separator: " ", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let value = String(parts[1])
                switch parts[0] {
                case "branch.oid": oid = value
                case "branch.head":
                    if value == "(detached)" { s.detached = true } else { s.branch = value }
                case "branch.upstream": s.hasUpstream = true
                case "branch.ab":
                    for token in value.split(separator: " ") {
                        if token.hasPrefix("+") { s.ahead = Int(token.dropFirst()) ?? 0 }
                        if token.hasPrefix("-") { s.behind = Int(token.dropFirst()) ?? 0 }
                    }
                default: break
                }
                continue
            }
            switch line.first {
            case "1", "2":
                // "1 XY ..." / "2 XY ..." — XY ở ký tự 2-3.
                let xy = line.dropFirst(2).prefix(2)
                guard xy.count == 2 else { continue }
                s.changedFiles += 1
                if xy.first != "." { s.staged += 1 }
                if xy.last != "." { s.modified += 1 }
            case "u":
                s.conflicted += 1
                s.changedFiles += 1
            case "?":
                s.untracked += 1
                s.changedFiles += 1
            default: break // "!" (ignored) và dòng lạ
            }
        }
        if s.detached {
            if let oid, oid != "(initial)" { s.branch = String(oid.prefix(7)) }
        }
        return s
    }
}

/// Đọc trạng thái git (chỉ đọc). Blocking: gọi từ nền, không gọi trên main.
public struct GitStatusReader: Sendable {
    /// `xcode-select -p` chỉ chạy một lần mỗi process. Không có Command Line Tools thì `/usr/bin/git`
    /// sẽ bật hộp thoại cài đặt, nên không bao giờ được gọi.
    public static let developerToolsInstalled: Bool =
        ProcessRunner.run("/usr/bin/xcode-select", ["-p"], timeout: 3) != nil

    private let toolsAvailable: @Sendable () -> Bool
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 3,
                toolsAvailable: @escaping @Sendable () -> Bool = { GitStatusReader.developerToolsInstalled }) {
        self.timeout = timeout
        self.toolsAvailable = toolsAvailable
    }

    /// Thư mục gốc repo (có `.git` là thư mục hoặc file worktree/submodule), đi ngược lên từ `url`.
    public static func repoRoot(of url: URL) -> URL? {
        var dir = url.standardizedFileURL
        let fm = FileManager.default
        while true {
            if fm.fileExists(atPath: dir.appendingPathComponent(".git").path) { return dir }
            // "/".deletingLastPathComponent() là "/.." (không phải "/"), nên phải chuẩn hoá rồi mới so sánh.
            let parent = dir.deletingLastPathComponent().standardizedFileURL
            if parent.path == dir.path || dir.path == "/" { return nil }
            dir = parent
        }
    }

    /// nil khi không phải repo, thiếu Command Line Tools, hết giờ hoặc git lỗi.
    public func summary(for dir: URL) -> GitSummary? {
        guard Self.repoRoot(of: dir) != nil, toolsAvailable() else { return nil }
        // --no-optional-locks: lệnh chỉ đọc, không tranh index.lock với git của người dùng.
        guard let data = ProcessRunner.run(
            "/usr/bin/git",
            ["--no-optional-locks", "-C", dir.path, "status", "--porcelain=v2", "--branch", "--untracked-files=normal"],
            timeout: timeout) else { return nil }
        return GitStatus.parse(String(decoding: data, as: UTF8.self))
    }
}
