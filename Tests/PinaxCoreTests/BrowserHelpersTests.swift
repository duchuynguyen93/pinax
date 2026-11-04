import Testing
import Foundation
@testable import PinaxCore

@Suite struct BrowserHelpersTests {
    @Test func nameSelectionStripsExtension() {
        #expect(FileNameSelection.length(of: "report.pdf", stripExtension: true) == 6)
        #expect(FileNameSelection.length(of: "archive.tar.gz", stripExtension: true) == 11)
        #expect(FileNameSelection.length(of: "README", stripExtension: true) == 6)
        #expect(FileNameSelection.length(of: ".gitignore", stripExtension: true) == 10)
        #expect(FileNameSelection.length(of: "trailing.", stripExtension: true) == 9)
        #expect(FileNameSelection.length(of: "my folder.d", stripExtension: false) == 11)
        // UTF-16: "é" 1 đơn vị, emoji 2 đơn vị.
        #expect(FileNameSelection.length(of: "é😀.txt", stripExtension: true) == 3)
    }

    @Test func openWithOrdersDefaultFirstThenByName() {
        func u(_ n: String) -> URL { URL(fileURLWithPath: "/Applications/\(n).app") }
        let entries = OpenWithOrdering.order(apps: [u("Zed"), u("Preview"), u("Atom"), u("Preview")], defaultApp: u("Preview")) {
            $0.deletingPathExtension().lastPathComponent
        }
        #expect(entries.map(\.name) == ["Preview", "Atom", "Zed"])
        #expect(entries.map(\.isDefault) == [true, false, false])
    }

    @Test func openWithKeepsDefaultNotInList() {
        let d = URL(fileURLWithPath: "/Applications/Safari.app")
        let entries = OpenWithOrdering.order(apps: [], defaultApp: d) { $0.lastPathComponent }
        #expect(entries.count == 1 && entries[0].isDefault)
        #expect(OpenWithOrdering.order(apps: [], defaultApp: nil) { $0.lastPathComponent }.isEmpty)
    }

    @Test func gitLabels() {
        let s = GitSummary(branch: "main", ahead: 2, behind: 0, staged: 1, modified: 2, untracked: 3, conflicted: 0, changedFiles: 5)
        #expect(s.aheadBehindLabel == "↑2")
        #expect(s.totalChanges == 5)
        #expect(s.changeBreakdown.map(\.kind) == [.staged, .modified, .untracked])
        #expect(s.changeBreakdown.map(\.count) == [1, 2, 3])
        #expect(GitSummary(ahead: 1, behind: 4).aheadBehindLabel == "↑1 ↓4")
        #expect(GitSummary().aheadBehindLabel == nil)
        #expect(GitSummary().changeBreakdown.isEmpty)
    }
}
