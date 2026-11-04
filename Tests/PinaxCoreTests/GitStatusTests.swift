import Testing
import Foundation
@testable import PinaxCore

@Suite struct GitStatusParserTests {
    @Test func clean() {
        let s = GitStatus.parse("""
        # branch.oid 1111111111111111111111111111111111111111
        # branch.head main
        # branch.upstream origin/main
        # branch.ab +0 -0
        """)
        #expect(s.branch == "main" && !s.detached && s.hasUpstream)
        #expect(s.ahead == 0 && s.behind == 0 && s.isClean && s.changedFiles == 0)
    }

    @Test func aheadBehind() {
        let s = GitStatus.parse("# branch.oid abc\n# branch.head feature/x\n# branch.upstream origin/feature/x\n# branch.ab +3 -12\n")
        #expect(s.branch == "feature/x" && s.ahead == 3 && s.behind == 12)
    }

    @Test func detached() {
        let s = GitStatus.parse("# branch.oid 0123456789abcdef0123456789abcdef01234567\n# branch.head (detached)\n")
        #expect(s.detached && s.branch == "0123456" && !s.hasUpstream)
    }

    @Test func untrackedModifiedStaged() {
        let s = GitStatus.parse("""
        # branch.oid a
        # branch.head main
        1 M. N... 100644 100644 100644 aaa bbb staged.txt
        1 .M N... 100644 100644 100644 aaa bbb modified.txt
        1 MM N... 100644 100644 100644 aaa bbb both.txt
        1 A. N... 000000 100644 100644 000 bbb added.txt
        2 R. N... 100644 100644 100644 aaa bbb R100 new name.txt\told.txt
        ? untracked one.txt
        ? other.txt
        ! ignored.log
        """)
        #expect(s.staged == 4)      // staged, both, added, renamed
        #expect(s.modified == 2)    // modified, both
        #expect(s.untracked == 2)
        #expect(s.conflicted == 0)
        #expect(s.changedFiles == 7)
        #expect(!s.isClean)
    }

    @Test func conflict() {
        let s = GitStatus.parse("""
        # branch.oid a
        # branch.head main
        u UU N... 100644 100644 100644 100644 aaa bbb ccc conflict.txt
        1 .M N... 100644 100644 100644 aaa bbb other.txt
        """)
        #expect(s.conflicted == 1 && s.modified == 1 && s.staged == 0 && s.changedFiles == 2)
    }

    @Test func initialRepoNoCommits() {
        let s = GitStatus.parse("# branch.oid (initial)\n# branch.head main\n? a.txt\n")
        #expect(s.branch == "main" && s.untracked == 1 && !s.detached)
    }

    @Test func emptyAndGarbage() {
        #expect(GitStatus.parse("") == GitSummary())
        #expect(GitStatus.parse("\n\nweird line\n# branch.ab\n").changedFiles == 0)
    }
}

@Suite struct GitStatusReaderTests {
    private func git(_ dir: URL, _ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir.path] + args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0, "git \(args)")
    }

    @Test(.enabled(if: GitStatusReader.developerToolsInstalled, "needs Command Line Tools"))
    func readsTempRepo() throws {
        let box = try Sandbox()
        let repo = box.home.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: repo.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try git(repo, ["init", "-q", "-b", "main"])
        try Data("a".utf8).write(to: repo.appendingPathComponent("staged.txt"))
        try git(repo, ["add", "staged.txt"])
        try Data("b".utf8).write(to: repo.appendingPathComponent("sub/untracked.txt"))

        let reader = GitStatusReader()
        let s = try #require(reader.summary(for: repo.appendingPathComponent("sub")))
        #expect(s.branch == "main" && !s.detached)
        #expect(s.staged == 1 && s.untracked == 1 && s.modified == 0)
        #expect(GitStatusReader.repoRoot(of: repo.appendingPathComponent("sub"))?.standardizedFileURL.path == repo.standardizedFileURL.path)
    }

    @Test func notARepoReturnsNilWithoutSpawning() throws {
        let box = try Sandbox()
        // Sandbox nằm trong thư mục tạm, không có .git phía trên → nil.
        #expect(GitStatusReader.repoRoot(of: box.downloads) == nil)
        #expect(GitStatusReader(toolsAvailable: { true }).summary(for: box.downloads) == nil)
    }

    @Test func toolsMissingNeverRunsGit() throws {
        let box = try Sandbox()
        try FileManager.default.createDirectory(at: box.home.appendingPathComponent(".git"), withIntermediateDirectories: true)
        #expect(GitStatusReader(toolsAvailable: { false }).summary(for: box.home) == nil)
    }
}
