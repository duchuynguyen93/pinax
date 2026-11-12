import Testing
import Foundation
@testable import PinaxCore

@Suite struct CloudLocationsTests {
    private func makeRoot(dirs: [String], files: [String] = []) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("pinax-cloud-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for d in dirs { try FileManager.default.createDirectory(at: root.appendingPathComponent(d), withIntermediateDirectories: true) }
        for f in files { FileManager.default.createFile(atPath: root.appendingPathComponent(f).path, contents: Data()) }
        return root
    }

    @Test func namesAndAccounts() throws {
        let root = try makeRoot(dirs: ["GoogleDrive-a@b.com", "Dropbox", "OneDrive-Personal", "Box-Work"])
        defer { try? FileManager.default.removeItem(at: root) }
        let list = CloudLocations.list(root: root)
        #expect(list.map(\.service) == ["Box", "Dropbox", "Google Drive", "OneDrive"])
        let g = try #require(list.first { $0.service == "Google Drive" })
        #expect(g.account == "a@b.com")
        #expect(g.url.lastPathComponent == "GoogleDrive-a@b.com")
        #expect(list.first { $0.service == "Dropbox" }?.account == nil)
        #expect(list.first { $0.service == "OneDrive" }?.account == "Personal")
    }

    @Test func multipleAccountsSameService() throws {
        let root = try makeRoot(dirs: ["GoogleDrive-b@x.com", "GoogleDrive-a@x.com"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(CloudLocations.list(root: root).map(\.account) == ["a@x.com", "b@x.com"])
    }

    @Test func unknownPrefixKeepsRawName() throws {
        let root = try makeRoot(dirs: ["Foo-bar"])
        defer { try? FileManager.default.removeItem(at: root) }
        let l = try #require(CloudLocations.list(root: root).first)
        #expect(l.service == "Foo-bar")
        #expect(l.account == nil)
    }

    @Test func filesIgnoredAndMissingRoot() throws {
        let root = try makeRoot(dirs: [], files: ["Dropbox", ".DS_Store"])
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(CloudLocations.list(root: root).isEmpty)
        #expect(CloudLocations.list(root: root.appendingPathComponent("nope")).isEmpty)
    }
}

@Suite struct CutStateTests {
    @Test func activeOnlyWhileChangeCountMatches() {
        let s = CutState(changeCount: 7, paths: ["/a/b"])
        #expect(s.isActive(currentChangeCount: 7))
        #expect(!s.isActive(currentChangeCount: 8))
        #expect(s.isCut("/a/b", currentChangeCount: 7))
        #expect(!s.isCut("/a/c", currentChangeCount: 7))
        #expect(!s.isCut("/a/b", currentChangeCount: 9))
    }
}
