import Testing
import Foundation
@testable import PinaxCore

@Suite struct SelectionTests {
    func cand(_ path: String, kind: ReasonKind = .other) -> Candidate {
        Candidate(url: URL(fileURLWithPath: path), size: 10,
                  fingerprint: FileFingerprint(size: 10, modified: Date(timeIntervalSince1970: 0)),
                  reason: "", reasonKind: kind, lastUsed: nil, preselected: false)
    }

    @Test func parentCoversChild() {
        let parent = cand("/tmp/pxsel/a")
        let child = cand("/tmp/pxsel/a/b/c.txt")
        let other = cand("/tmp/pxsel/z.txt")
        let eff = Selection.effectiveSelection([child, parent, other])
        #expect(Set(eff.map(\.url.path)) == ["/tmp/pxsel/a", "/tmp/pxsel/z.txt"])
        #expect(eff.count == 2)
        #expect(!eff.contains(child))
    }

    @Test func sharedNamePrefixIsNotNested() {
        let eff = Selection.effectiveSelection([cand("/tmp/pxsel/foo"), cand("/tmp/pxsel/foobar")])
        #expect(eff.count == 2)
    }

    @Test func samePathCollapses() {
        let eff = Selection.effectiveSelection([cand("/tmp/pxsel/x"), cand("/tmp/pxsel/x")])
        #expect(eff.count == 1)
    }

    @Test func keeperSelectedIsConflict() {
        let keeper = cand("/tmp/pxsel/orig.bin")
        let dup = cand("/tmp/pxsel/copy.bin", kind: .duplicateOf(keeper.url))
        let conflicts = Selection.duplicateKeeperConflicts(selected: [keeper, dup])
        #expect(conflicts == [dup])
    }

    @Test func keeperInsideSelectedFolderIsConflict() {
        let folder = cand("/tmp/pxsel/folder")
        let dup = cand("/tmp/pxsel/copy.bin", kind: .duplicateOf(URL(fileURLWithPath: "/tmp/pxsel/folder/orig.bin")))
        #expect(Selection.duplicateKeeperConflicts(selected: [folder, dup]) == [dup])
    }

    @Test func noConflictOtherwise() {
        let dup = cand("/tmp/pxsel/copy.bin", kind: .duplicateOf(URL(fileURLWithPath: "/tmp/pxsel/orig.bin")))
        let sibling = cand("/tmp/pxsel/orig.bin2")
        #expect(Selection.duplicateKeeperConflicts(selected: [dup, sibling]).isEmpty)
        #expect(Selection.duplicateKeeperConflicts(selected: [dup]).isEmpty)
    }
}
