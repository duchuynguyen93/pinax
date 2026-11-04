import Testing
import Foundation
@testable import PinaxCore

@Suite struct FolderResolveTests {
    let box: Sandbox
    init() throws { box = try Sandbox() }

    @Test func existingFolderReturnsItself() {
        #expect(FolderResolve.nearestExistingFolder(box.downloads).path == box.downloads.path)
    }

    @Test func missingChildFallsBackToNearestParent() {
        let gone = box.downloads.appendingPathComponent("a/b/c")
        #expect(FolderResolve.nearestExistingFolder(gone).path == box.downloads.path)
    }

    @Test func fileFallsBackToItsFolder() throws {
        let f = try box.write("x.txt")
        #expect(FolderResolve.nearestExistingFolder(f).path == box.downloads.path)
    }

    @Test func nothingExistsReturnsRoot() {
        #expect(FolderResolve.nearestExistingFolder(URL(fileURLWithPath: "/no-such-dir-\(UUID().uuidString)/x")).path == "/")
    }
}
