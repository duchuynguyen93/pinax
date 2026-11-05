import Testing
import Foundation
@testable import PinaxCore

@Suite struct WorkspaceStoreTests {
    let box: Sandbox
    var url: URL { box.root.appendingPathComponent("support/workspaces.json") }

    init() throws { box = try Sandbox() }

    @Test func addPersistsAndReloads() throws {
        let s = WorkspaceStore(url: url)
        let w = try s.add(name: "Work", tabs: [TabState(left: "/a", right: "/b", viewMode: "list", activeRight: true)])
        let again = WorkspaceStore(url: url)
        #expect(again.all == [w])
    }

    @Test func renameUpdateDelete() throws {
        let s = WorkspaceStore(url: url)
        let w = try s.add(name: "A", tabs: [])
        try s.rename(id: w.id, to: "B")
        try s.update(id: w.id, tabs: [TabState(left: "/x", viewMode: "icons")])
        let r = WorkspaceStore(url: url).all
        #expect(r.first?.name == "B")
        #expect(r.first?.tabs == [TabState(left: "/x", right: nil, viewMode: "icons", activeRight: false)])
        try s.delete(id: w.id)
        #expect(WorkspaceStore(url: url).all.isEmpty)
    }

    @Test func corruptFileIsMovedAside() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: url)
        let s = WorkspaceStore(url: url)
        #expect(s.all.isEmpty)
        #expect(FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("workspaces.corrupt.json").path))
        _ = try s.add(name: "N", tabs: [])
        #expect(WorkspaceStore(url: url).all.count == 1)
    }
}
